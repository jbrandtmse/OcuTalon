---
title: 'Story 25.4: Assign approver and viewer roles in Settings'
type: 'feature'
created: '2026-11-13'
status: 'done'
baseline_revision: '2226912e4139b7b626adb9ca52e472795e939420'
baseline_commit: '0d9406059723f0dd6c44b895747f3b2cfcd73b2d'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md'
  - '{project-root}/_bmad-output/implementation-artifacts/epic-25-context.md'
  - '{project-root}/_bmad/custom/skill-rules.md'
warnings: [oversized]
deferred:
  - summary: >-
      A Settings audit entry for a user whose name ends in a sensitive suffix (token, secret, password, pwd, apikey, username, userid and the like) is written with from and to redacted.
    evidence: |-
      Bridge.Audit.Record blanks from and to when Redact.SensitiveKey flags the setting name, and Assign's setting is roles.<userName>, so a user named for example svc.token keeps its entry but loses the role lists. The setting shape roles.<user> is pinned by the Matrix, so the fix (a different member for the user, or an exemption for roles.*) changes a pinned shape.
    location: >-
      src/ocutalon/cls/OcuTalon/Install/Step/Roles.cls Assign; src/bridge/cls/OcuTalon/Bridge/Audit.cls Record
    severity: low
---

<intent-contract>

## Intent

**Problem:** Step 6 needs approvers and viewers. Today no admin can grant `OcuTalonApprover` or `OcuTalonViewer`: `Install.Step.Roles.Assign` and `Holders` are Story 37.1's stubs (5003), Settings has no Roles section, and a user who holds only `OcuTalonViewer` is turned away by the post-sign-in check (`Web/Public/Shell.cls:27,145`).

**Approach:** Build the two Lane A methods, as the lead's dispatch moved them into this story (AD-24 S2 and Planner ruling V3: an allowlist of exactly two roles, refusals, one audit entry per change, refused on the online demo). Add an admin-only Settings > Roles section. Its routes reach `SettingsOps` through `SecretHandoff` in both directions, so no other user's name enters a traced message (V4). Admit a viewer-only user as read-only: the page hides every control that changes state, and the API refuses every state-changing request from a viewer with 403. The section stays hidden until Story 26.4 creates the roles (a `/v1/state` capability flag, following 25.3's ruling 4).

## Boundaries & Constraints

**Always:**
- `Assign` works from an allowlist of exactly `OcuTalonApprover` and `OcuTalonViewer`. Role names are compared without regard to case. It refuses every other role: `OcuTalonAdmin`, `OcuTalonUser`, `OcuTalonTraceViewer`, `OcuTalonWebhook`, any `OcuTalonApprover_<kind>`, every `%` role (`%All` included) and any unknown name. It also refuses the installer-managed accounts, an unknown or empty user, the online demo, and a caller job without `%Admin_Secure:USE`. Each refusal returns an error that names what was refused, and nothing changes.
- Every effective grant and every effective removal writes exactly one IRIS audit entry of type `Settings` through `OcuTalon.Bridge.Audit.Record`. The entry names the acting admin, the target user and the user's OcuTalon roles before and after. When the user already is in the requested state, there is no change and no entry. If the entry cannot be written, the role change is put back and `Assign` returns an error.
- The target user name and the role cross between the REST process and `SettingsOps` only through `OcuTalon.Core.SecretHandoff`, in both directions:
  - `SaveSettings.Changes` is exactly `{"handoff": "<uri>"}`.
  - `ListRoles`' `CommandResult.Data` is exactly `{"handoff": "<uri>"}`.
  - No message body, `CommandResult.Message`, event-log line, trace or global holds another user's name. The only places it appears are the IRIS audit entry and the HTTP response to the admin.
- The REST process discards every handoff uri it created on every path. It takes the reverse uri once.
- Both Roles routes are admin-only. `Api.OnPreDispatch` checks this, and `Web.RoleSettings` checks it again for each route. On the online demo, each route answers 409 `not_available` before the body is read.
- Viewer rules:
  - A viewer-only user is one who holds `OcuTalonViewer` and not `OcuTalonUser`.
  - The post-sign-in check admits such a user, and so do the API role check, the session attach and the WebSocket admission.
  - Every request from that user whose method is not GET is refused with 403 `read_only` in `Api.OnPreDispatch`, before anything is read or submitted.
  - The one exception is `POST /v1/session/end`, which signs the user out.
- Visible strings are exactly those of `## Planner Gate` → PUBLIC TEXT.
- Every test that mutates security objects (users, roles, role grants) runs only on a throwaway. It uses the THROWAWAY/CI guard of `Test.Core.AnswersInWebRoles.Reason`, creates the fixture roles only when they are absent, and removes only what it created.

**Never:**
- Create the step-6 roles, their resources or grants in the installer.
- Change `Install.Step.Users` (`DEMOROLES`, the README account), `Install.Step.Web` grants or `MatchRoles`, or any role's resources.
- Widen `OcuTalonUser`.
- Touch `Approval.MayAnswer`, `Answer`, `AnswersIn`, `AnswerOps` or `Decide`.
- Grant a per-kind role through OcuTalon.
- Show a Roles section or a settings link on the online demo, or before Story 26.4's roles exist.
- Put another user's name in a command property, a `CommandResult`, a log line or a global.
- Add a live unit, a CI group, a More to try item or a GUIDE.md line.
- Edit the spine's existing sentences. The lead applies the replacements listed under Design Notes.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Admin lists | README admin, `GET /api/v1/settings/roles` | 200 `{"users":[{user, roles, managed}]}`: every user holding a role whose name starts with `OcuTalon`, sorted by name without regard to case. `roles` holds only the OcuTalon roles, sorted. `managed` is true for the installer-managed accounts. The list comes back through a handoff uri. | 500 `server_error` when the command or the take fails |
| Admin grants | `POST` `{"user":"ZzTarget","role":"OcuTalonViewer","grant":true}` | 200 `{"result":"done","changed":true}`. The user holds the role. One `Settings` audit entry `roles.ZzTarget`, from `OcuTalonUser`, to `OcuTalonUser,OcuTalonViewer`. The page shows the step-2 text. | none |
| Repeat | The same body again; or a removal of a role the user does not hold | 200 `changed:false`, no audit entry | none |
| Admin removes | `grant:false` for a held role | 200 `changed:true`, one audit entry | none |
| Role refused (each) | `OcuTalonAdmin`, `OcuTalonUser`, `OcuTalonTraceViewer`, `OcuTalonWebhook`, `OcuTalonApprover_resend`, `%All`, `%Manager`, `ZzNoSuchRole` | 400 `bad_settings`, `fields ["role"]`, `reason "role"`. Nothing changes and no audit entry is written. | — |
| User refused (each) | `OcuTalonService`, `OcuTalonWorkflow`, `OcuTalonSqlReader`, an account whose FullName is `Users.#MARKER`, the public settings' `demoUser` / `readonlyUser` | 400, `fields ["user"]`, `reason "user_managed"`. Nothing changes. | — |
| Unknown user | `ZzNoSuchUser`, `""`, or a name of 161 characters | 400, `fields ["user"]`, `reason "user_unknown"` | — |
| Bad shape | A missing or extra key, `grant` not a boolean, `user` or `role` not a string | 400 `bad_settings` naming the fields. No handoff is made and no command is submitted. | — |
| Not admin | LIVE `OcuTalonUser` fixture, GET or POST | 403 `not_admin` | — |
| Signed out | No session | 401 `signed_out` | — |
| Online demo | `onlineDemo` 1, admin, GET or POST (a malformed body included) | 409 `not_available`. The body is never read, and no handoff or command is made. `Assign` and `Holders` refuse there too. | — |
| No privilege | `Assign`/`Holders` in a job without `%Admin_Secure:USE` | An error naming `%Admin_Secure`. Nothing changes. | — |
| Viewer signs in | A user holding only `OcuTalonViewer` | The page loads (no no-role message) and `/v1/state` has `viewer` true and `admin` false. There is no composer (the viewer line shows in its place) and no Approve, Reject, Dismiss, Break the feed or other state-changing control. History and Usage open. | — |
| Viewer writes | That user, every non-GET route of `Web.Api` and the classes it forwards to | 403 `read_only`, with nothing submitted or changed. `POST /v1/session/end` still signs the user out. | — |
| Viewer + user | Holds `OcuTalonViewer` and `OcuTalonUser` | Treated as a user: `viewer` is false and nothing is refused | — |
| Before 26.4 | The real state on this branch (no `STEP6ROLES`) | `rolesAssignable` is false, and the Settings nav shows no Roles | — |
| Demo account | `onlineDemo` 1, roles `OcuTalonUser,OcuTalonTraceViewer` + fixture `OcuTalonApprover` | `admin`, `viewer` and `rolesAssignable` are false, so there is no settings link and no Roles section. It answers its own session's request, and gets `not_visible` for another session's. | — |
| Integration (Rule 1) | The page's Roles section → `Web.RoleSettings` → `SettingsOps` → `Roles.Assign` / `Holders` on the real production | The grant the page makes appears in the page's next list, and in `$SYSTEM.Security.GetUserRecursedRoleSet` | — |

</intent-contract>

## Code Map

All paths are relative to `src/ocutalon/cls/OcuTalon/` unless they start with `web/`, `docker/`, `ci/` or `_bmad-output/`.

**Lane A role methods (built here):**
- `Install/Step/Roles.cls`:
  - Stubs `Assign` :29-33 and `Holders` :38-42. Their doc comments already state the contract.
  - `ROLEPREFIX` :12 and `FORBIDDEN` :15.
  - The `%SYS` pattern is in `ResourceExists` :91 and `Apply` :99-126 (`New $Namespace`).
  - The sibling for a public run-time privilege method is `Install/Step/Mcp.cls:55-70` (`Grant`/`Revoke`).
- `Install/Step/Users.cls`. Read it; do not change it.
  - `USER` "ocutalon" :30 (the README account; seed and never rewritten, :5-7), `SERVICEUSER` :39, `DEMOROLES` :45 and `MARKER` :54.
  - The demo and read-only names come from `Data.Public.Settings.Get("demoUser"/"readonlyUser")` (`PublicAccounts` :386-421, which compares names in lower case).
  - The FullName check is `Foreign` :431.
- `src/bridge/cls/OcuTalon/Bridge/Approval.cls:44`: `WORKFLOWUSER` "OcuTalonWorkflow". Read only.
- `src/bridge/cls/OcuTalon/Bridge/Audit.cls`:
  - `Record("Settings", data)` :90.
  - The shape is `setting,from,to` plus `irisUser,sessionRef,channel` (:21, :31). `setting` and `irisUser` must not be empty, and `channel` must be one of `Bridge.Msg.Enum` `CHANNEL`.
  - The description is "Setting <setting> changed".
- IRIS API (`irissys/Security/Users.cls`): `AddRoles` :276, `RemoveRoles` :592, `Exists` :405, `Get` :482, and the query `List(Names, Roles, ...)` :666 with columns `Name, Enabled, Roles`.
  - Measured on slot A: `List("*","*")` returns rows. Slot A has no OcuTalon roles, because it never runs the installer.

**Viewer admission (Lane B):**
- `Web/Public/Shell.cls`:
  - `ROLE` :27.
  - `HasRole()` :145-148 checks the whole name in `$Roles`. It is also called by `Web/SessionEvents.cls:47` (session attach) and `Web/Live.cls:81` (WebSocket), so those follow the change.
- `Web/Public/Login.cls:29`: `ERRORNOROLE`, unchanged.

**API (Lane B):**
- `Web/Api.cls` (contended):
  - UrlMap :253-297 (Maps :292-296).
  - `OnPreDispatch` :313-333: role → admin → envelope → body size.
  - `HasUserRole` :336, `Roles()` :342 (the test seam), `IsAdmin` :348, `IsSettingsUrl` :354.
  - `StateBody` :1271, with its flags at :1292-1295.
  - Doc lines :37-58 (settings) and :1259-1261 (state).
- `Web/HookSettings.cls`. This is the sibling for the new forwarded class:
  - The class doc :1-17.
  - UrlMap `Url=""` :23-30.
  - `OnlineDemo()` :35 and `Refusal()` :41-46.
  - `Hand` :119-137: `Put`, then Submit inside a Try, then `Discard` always.
- `Core/SecretHandoff.cls`:
  - `Put` :25. Any non-empty string; measured on slot A: 64 KB, 1 MB and 3.6 MB strings round-trip.
  - `Take(uri, .s, timeoutSec=5)` :51 and `Discard` :76.
- `Core/SettingsOps.cls` (contended):
  - `Carry` :176-193.
  - `AuditData` :226 and `WriteAudit` :247: for reference only; `Assign` writes the roles entry.
  - `OnlineDemo` :696, `Result` :802, `XData Sections` :882-912.
  - `Values` :938, whose skip condition is at :943.
  - `Save` :1005-1035, with the email branch at :1015.
  - `TakeSecret` :2319 (used by `CreateWebhook` :2247, which takes before its demo refusal).
- `Core/CommandsIn.cls`:
  - `XData Routes` :325, with the rows `SaveSettings` :341 and `CreateWebhook` :362.
  - `Route` :221-238 strips `OcuTalon.Msg.Command.`.
- `Msg/Command/SaveSettings.cls`: `Slug` (MAXLEN 32), `Changes` and `ActingUser`. The base class adds `Origin` and `SessionRef`.
- `Msg/CommandResult.cls`: `Ok`, `Message`, `Outcome` and `Data` (MAXLEN "").

**Tests (siblings):**
- `Test/Bridge/Api.cls:140-160`: `TestRoleStubs` pins the stubs and must change. The README account is `ApprovalRows.#ANSWERER`.
- `Test/Contract/Ac.cls`:
  - Signatures :392-393 (`Assign`, `Holders`), compared on their leading arguments (:156-163).
  - The floor `count >= 93` is at :165, and the doc count at :18.
- `Test/Web/HookSettingsApi.cls`:
  - `TestNotAdmin` :212.
  - `TestOnlineDemo` :238.
  - `TestSecretNeverStored` :288, the leak-scan model.
  - Its probe is `Test/Web/HookSettingsProbe.cls`.
- `Test/Web/ApiProbe.cls`: overrides `Roles` :60, `HasUserRole` :67 and the submit seams.
- `Test/Web/SettingsApi.cls`: `TestNonAdminIs403Everywhere` :110, `PreDispatch` :820, `Call` :843, and `TestStateHasAdmin` :774.
- `Test/Web/Api.cls:132`: the `/v1/state` key order.
- `Test/Core/SecretHandoff.cls`: `Leaks(text)` :177 and `TableHolds` :203.
- `Test/Core/AnswersInWebRoles.cls`:
  - `Reason` :93, the throwaway guard.
  - `CreateUser` :382.
  - A job logs in as a fixture user with the application roles (`Roles()` :397).
- `Test/Core/SettingsWebhooks.cls`: the sibling test of a `SettingsOps` handoff verb.

**Live and e2e:**
- `docker/tests/lib-live.sh:501`: `live_fixture_user`.
- `docker/tests/test-sign-in.sh`:
  - Fixture users :248-288.
  - The env passed to Playwright :338-356.
  - The `show_log` redaction :331.
  - Shared by `test-sign-in-2.sh` and `-3`.
- The role-fixture pattern is `docker/tests/test-install-start.sh:256-260`.
- `web/playwright.config.ts:52`: `SIGN_IN_2_DIRS` includes `settings`. `api/` and `sign-in/` run in chromium (`live:sign-in`).
- `web/e2e/sign-in/helpers.ts`: `README_ACCOUNT` :16, `signIn` :70 and `signInReadme` :104.
- The `no_role` pin is `web/e2e/api/history.spec.ts:281-289`.

**Web (Lane B):**
- `web/src/app/settings/settings-view.ts`:
  - The title :30, `sectionsName` :32 and the labels :35-40.
  - `saved` :43 (the step-2 text), `failed` :45, `denied` :46.
  - `SETTINGS_SECTIONS` :128-136, `sectionSlug` :141.
  - `refusalKind` :237-252.
- `web/src/app/settings/settings-page.ts`: the nav :49-53, the `h2` :58 and the `@switch` :62-94.
- `web/src/app/settings/webhooks-section.ts` and `webhooks-view.ts`: the list-with-actions sibling (the row group :104, `app-server-button` :126, the saved line :132, the load error with Retry :34). Also `refusal.ts:11` `refusalOf`.
- `web/src/app/shared/demo-view.ts:29`: the single-reader sibling for the new `viewer-view.ts`.
- `web/src/app/api/api-types.ts:44-62`: `StateSnapshot` (`admin` :58, `filesReadable` :62).
- `web/src/app/api/api-client.ts`: the route methods (`postGuideMarker` :173).
- `web/src/app/header/header-nav.ts:24-25,71`: the Settings link, shown when `admin`.
- Viewer guards, at the line where each control is mounted or rendered:
  - `chat/chat-panel.ts:192` (composer) and the chat drop (:132 doc)
  - `approvals/approval-request-card.ts:174-202` (Approve/Reject)
  - `incidents/incident-dismiss.ts:51`
  - `feed/break-feed-box.ts:45`
  - `guide/demo-guide.ts:221` (Run again) and :104-107 (markers)
  - `chat/try-it-row.ts:33`
  - `guide/more-to-try.ts:87`
  - `chat/got-it.ts`
  - `chat/noise-control.ts:49`
  - `rail/status-rail.ts:101-107` (the Telegram, persona, heartbeat and memory cards)
  - `documents/documents-page.ts:64,66,94`
  - `mailbox/simulated-mailbox.ts:121,137,181`
- UX: `_bmad-output/planning-artifacts/ux-designs/ux-OcuTalon-2026-10-16/EXPERIENCE.md` :44, :404-405, :1099-1100 and :1143. UX-DR141 and UX-DR147 are at `epics.md:473,479`. PRD FR-11 is at `prds/prd-OcuTalon-2026-10-16/prd.md:375-388`.

## Tasks & Acceptance

**Execution:**
- [x] Task 0 (DONE in implement pass 1; results under Design Notes "Measured (Task 0, implement stage 2026-11-13 ...)", not re-run):
  - (a) In a production job (`SettingsOps`' context), `Security.Users.AddRoles` and `RemoveRoles` change only the named role.
  - (b) `$SYSTEM.Security.Check("%Admin_Secure","USE")` is 1 in the `SettingsOps` job and 0 in a job logged in as a fixture user holding `OcuTalonAdmin` plus the application roles.
  - (c) After `RemoveRoles(viewer,"OcuTalonViewer")`, does a signed-in viewer's CSP session keep `$Roles` until it signs out (`curl GET /v1/state` before and after)? This decides PUBLIC TEXT row 9 (Planner question 2).
  - (d) Read a `Settings` entry back from `%SYS.Audit` within the existing polling helper's timeout.
  - (e) A `SecretHandoff` put by the production job is taken by the CSP process (the cross-process direction). In-process is measured: up to 3.6 MB.
- [x] `Install/Step/Roles.cls` -- Replace the stubs:
  - Add `Parameter ASSIGNABLE = "OcuTalonApprover,OcuTalonViewer";`.
  - Add `Parameter SQLREADER = "OcuTalonSqlReader";` (AD-18's name; a refusal even before that user exists).
  - `ClassMethod Refusal(userName As %String, role As %String) As %String` returns `""` or one code:
    - `online_demo` (`Data.Public.Settings.Get("onlineDemo")`);
    - `role` (not in `ASSIGNABLE`, compared without regard to case);
    - `user_unknown` (empty, over 160 characters, or not `Security.Users.Exists`);
    - `user_managed` (`Users.#SERVICEUSER`, `Approval.#WORKFLOWUSER`, `SQLREADER`, the public `demoUser`/`readonlyUser`, compared in lower case, or a FullName equal to `Users.#MARKER`).
    - The README account is not managed (Planner question 3).
  - `Assign(userName, role, grant, Output changed, actingUser As %String = "", sessionRef As %String = "", channel As %String = "system") As %Status`. The leading arguments keep their pinned shape. In order:
    1. `changed` 0.
    2. `Refusal`, giving an error 5001 whose text names the code and the role or user.
    3. The `%Admin_Secure:USE` check.
    4. In `%SYS`: read the user's roles, and quit OK with no entry when there is nothing to change.
    5. `AddRoles` or `RemoveRoles` with the allowlist's spelling.
    6. Outside `%SYS`, `Bridge.Audit.Record("Settings", {setting "roles."_userName, from, to (the OcuTalon roles before and after, comma lists sorted), irisUser actingUser or $Username, sessionRef, channel})`. If that fails, put the role back and return the error.
    7. `changed` 1.
  - `Holders(Output users)`: the demo refusal and the privilege check. In `%SYS`, the `Security.Users:List` rows that hold any role starting with `ROLEPREFIX`, each as `{user, roles: [sorted OcuTalon roles], managed: (Refusal(user,"OcuTalonViewer") = "user_managed")}`, sorted by `$ZConvert(user,"L")` and then by name.
  - Rewrite the class doc lines and the method docs to state the built contract (Rule 14: the contract, not the history).
  - -- AC 1, AC 6; V3.
- [x] `Msg/Command/ListRoles.cls` (new; extends `OcuTalon.Msg.Command`, with no property) and `Core/CommandsIn.cls` -- one `XData Routes` row: `{"verb": "ListRoles", "owner": "SettingsOps", "origins": "web_admin"}`, plus one doc line. -- The read verb of the list.
- [x] `Core/SettingsOps.cls` -- The contended hunks under Design Notes:
  - `ListRoles(command)`:
    1. Refuse unless the origin is `web_admin`.
    2. Return `not_available` on the demo.
    3. Call `Install.Step.Roles.Holders`; 5003 gives `not_built`, any other error `failed`.
    4. `SecretHandoff.Put(users.%ToJSON(), .uri)`.
    5. Answer `Result(1,"done","",{"handoff":uri}.%ToJSON())`.
  - `SaveRoles(command, changes)`:
    1. The changes must be exactly `{handoff}`.
    2. `TakeSecret` first, always.
    3. The origin must be `web_admin`; `not_available` on the demo.
    4. Parse `{user, role, grant}`.
    5. `Roles.Refusal` gives `refused` with Data `{"fields":[<"role"|"user">],"reason":code}`.
    6. `Roles.Assign(user, role, grant, .changed, command.ActingUser, command.SessionRef, "web")`; an error gives `failed`.
    7. `done` with Data `{"changed":bool}`.
  - It writes no audit entry of its own (`Assign`'s is the change's entry, Planner question 6).
  - Update the class-doc lines.
  - -- AC 1, DW-1267.
- [x] `Web/RoleSettings.cls` (new; extends `OcuTalon.Web.Api`, the HookSettings pattern) and one `Map` line in `Web/Api.cls` -- UrlMap `Url=""` GET `List` and POST `Save`.
  - `Refusal()`: 403 `not_admin`, then 409 `not_available` with `MESSAGEROLESOFF`, before the body is read.
  - `List`:
    1. Submit `ListRoles` (`web_admin`).
    2. Map the outcomes: `not_available` 409, `not_built` 501, otherwise 500.
    3. Take the uri with `Take(uri,.json,5)`; a failure gives 500.
    4. Answer 200 `{"users": [...]}`.
  - `Save`:
    1. Parse the body, which must have exactly the keys `user` (a string of 1 to 160 characters), `role` (a string) and `grant` (a boolean). Otherwise answer 400 `bad_settings` with the fields, before any handoff.
    2. `Put({user,role,grant}.%ToJSON(), .uri)`.
    3. Submit `SaveSettings` with `Slug "roles"`, `Changes {"handoff":uri}`, `ActingUser $Username` and the session's `SessionRef`.
    4. `Discard(uri)` on every path, an exception included.
    5. Map the outcomes: `done` 200 `{"result":"done","changed"}`; `refused` 400 `bad_settings` with `{fields, reason}` and the reason's message (PUBLIC TEXT 12); `not_available` 409; `not_built` 501; anything else 500.
  - `ClassMethod RolesReady(roleClass As %String = "OcuTalon.Install.Step.Roles") As %Boolean` is 1 only when `$Parameter(roleClass,"STEP6ROLES")` is exactly 1. The argument is the test seam, as `Core.Files.Readable` does it.
  - -- AC 1, AC 4, AC 5, DW-1267.
- [x] `Web/Public/Shell.cls` -- Add `Parameter VIEWERROLE = "OcuTalonViewer";`.
  - `HasRole(roles As %String = {$Roles})` admits `ROLE` or `VIEWERROLE` by whole name.
  - New `ViewerOnly(roles As %String = {$Roles})`: holds `VIEWERROLE` and not `ROLE`.
  - Update the class doc.
  - -- AC 2.
- [x] `Web/Api.cls` -- The contended hunks under Design Notes:
  - The viewer block in `OnPreDispatch` right after the role check: a viewer-only user whose method is not `GET`, unless the request is `POST /v1/session/end`, gets `Fail(403,"read_only",..#MESSAGEREADONLY)`.
  - Private `ViewerOnly()` returns `Shell.ViewerOnly(..Roles())`, so the probe's `Roles` drives it.
  - `HasUserRole` keeps calling `Shell.HasRole()`.
  - `StateBody`: `admin` is `..IsAdmin() && '..ViewerOnly()`, and two booleans follow `filesReadable`: `viewer` (`..ViewerOnly()`) and `rolesAssignable` (onlineDemo off and `Web.RoleSettings.RolesReady()`).
  - Update the doc lines.
  - -- AC 2, AC 3.
- [x] `web/src/app/api/api-types.ts`, `api-client.ts` -- Add `viewer` and `rolesAssignable` to `StateSnapshot`, after `filesReadable`. Add `RoleHolder {user, roles, managed}` and the methods `listRoles()` and `saveRole(user, role, grant)`. -- AC 1, AC 2.
- [x] `web/src/app/shared/viewer-view.ts` (new, pure) -- `isViewer(snapshot)`, which only `snapshot?.viewer === true` makes true, and `VIEWER_TEXTS.line` (PUBLIC TEXT 14). It is the single reader, following `demo-view.ts`. -- AC 2.
- [x] The viewer guards. Each component's control is hidden when `isViewer(live.snapshot())`, with no new layout. -- AC 2.
  - `chat/chat-panel.ts`: no composer, `VIEWER_TEXTS.line` in its place, and no chat drop.
  - `approvals/approval-request-card.ts`: no Approve or Reject.
  - `incidents/incident-dismiss.ts`.
  - `feed/break-feed-box.ts`.
  - `guide/demo-guide.ts`: no Run again, and no marker posts.
  - `chat/try-it-row.ts`.
  - `guide/more-to-try.ts`: the item buttons.
  - `chat/got-it.ts` and `chat/noise-control.ts`.
  - `rail/status-rail.ts`: no Telegram, persona, heartbeat or memory card.
  - `documents/documents-page.ts`: no add, sample or remove.
  - `mailbox/simulated-mailbox.ts`: no Simulate, send or samples.
- [x] `web/src/app/settings/roles-view.ts` and `roles-section.ts` (new; siblings `webhooks-view.ts` and `webhooks-section.ts`), `settings-view.ts`, `settings-page.ts`:
  - `ROLES_TEXTS` (PUBLIC TEXT 2-8 and 11-12) and `roleOutcome(status, body)`: 403 is `denied`, 409 is `off`, a 400 with `reason` is that reason's text, and anything else is `failed`.
  - The section shows:
    - the intro and the per-kind note;
    - the list as one `role="group"` per user, labelled by the user name, with the roles as text and a Remove button for each assignable role it holds, or the "Managed by OcuTalon" text instead;
    - the empty text;
    - a grant form: a labelled text input, a labelled select with the two roles, and a Grant `app-server-button`;
    - after each change, the step-2 `saved` text, then the list reloaded;
    - refusals in a polite live region.
  - Add `roles` to `SETTINGS_SECTIONS` last, with the label `Roles`.
  - `settings-page.ts` shows the nav entry and `@case ('roles')` only when `admin && rolesAssignable && !onlineDemo` (an unknown or hidden slug goes to Models, as `sectionSlug` does).
  - -- AC 1, AC 5.
- [x] `docker/tests/lib-live.sh`, `docker/tests/test-sign-in.sh` -- Add `live_fixture_role <name>`, which creates a role with no resources in `%SYS` only when it is absent and prints `CHK|fixture-role|1`.
  - Before the users, create the fixture roles `OcuTalonApprover`, `OcuTalonApprover_` plus each of `resend,reroute,suspend,rollback,partner,email,tool`, and `OcuTalonViewer`.
  - Create the fixture users `ZzViewer` (`OcuTalonViewer`) and `ZzRoleTarget` (`OcuTalonUser`) with random passwords.
  - Pass them to Playwright as `OCUTALON_VIEWER_USER/_PASSWORD` and `OCUTALON_ROLETARGET_USER/_PASSWORD`, and add both passwords to the `show_log` redaction.
  - -- AC 6 fixture setup.
- [x] `Test/Install/RolesAssign.cls` (new; lane-a `@Install`; THROWAWAY guard) -- It covers:
  - one test method per refusal row of the matrix, each asserting the error names the role or user, the user's recursed role set is unchanged, and there is no new audit entry;
  - `%Admin_Secure` missing, through a job logged in as a fixture admin;
  - the online demo, with the public flag forced and restored;
  - grant and remove (`changed` 1, then 0), each with exactly one `Settings` entry read back by polling;
  - an audit failure that puts the role back (through a test subclass whose audit write fails);
  - `Holders`: sorted, OcuTalon roles only, `managed` set, refused on the demo.
  - The fixture roles and users have the prefix `ZzRolesA` and are removed before and after.
  - -- AC 1, AC 6; V3 "a test for each refusal".
- [x] `Test/Bridge/Api.cls` -- Replace `TestRoleStubs` with `TestRoleCalls`, which mutates nothing: `Assign("ocutalon","%All",0)` is a 5001 naming the role with the README roles unchanged; `Holders` does not answer 5003. Update the class doc. `Test/Contract/Ac.cls`: add `{"class":"OcuTalon.Install.Step.Roles","method":"Refusal","args":"userName,role","returns":"%String"}` and raise the floor and the doc count to 94. -- The contract.
- [x] `Test/Core/SettingsRoles.cls` (new; lane-b `@Core`; THROWAWAY guard; sibling `SettingsWebhooks`) -- For `ListRoles` and `SaveRoles` through `SettingsOps`:
  - `Changes` that are not exactly `{handoff}` are refused;
  - the uri is consumed on every outcome, the demo included;
  - a `system` origin is refused;
  - each refusal code maps to fields and reason;
  - a 5003 from a stub subclass gives `not_built`;
  - `Data` holds only the handoff or `changed`, never a name.
  - -- AC 1, DW-1267.
- [x] `Test/Web/RolesApi.cls` and `Test/Web/RoleSettingsProbe.cls` (new; lane-b rest; THROWAWAY guard for the production cases):
  - not admin 403 for GET and POST;
  - viewer-only POST 403 `read_only`;
  - the demo gives 409 for GET and POST with a malformed body, with no handoff resource made and no command submitted (probe counters);
  - each 400 shape;
  - a real grant and removal of a `ZzRoleLeak<random>` user through the production;
  - `SaveSettings.Changes` equals `{"handoff":"secret://handoff/<32 hex>"}`;
  - the leak scan: the fixture name is absent from `OcuTalon_Msg_Command.SaveSettings`, `OcuTalon_Msg_Command.ListRoles`, `OcuTalon_Msg.CommandResult` (every column), `Ens.MessageHeader.Description`, `Ens_Util.Log.Text` and every `^OcuTalon*` global (`Test.Core.SecretHandoff` `Leaks` and `TableHolds`), and present in the IRIS audit entry;
  - every uri is gone afterwards;
  - `GET` lists the fixture user;
  - `RolesReady` is 0 on this branch and 1 for a probe class with `STEP6ROLES = 1`.
  - -- AC 1, AC 4, AC 5, DW-1267.
- [x] `Test/Web/ViewerApi.cls` (new; lane-b rest; probe only, no mutation):
  - Enumerate every `Route` and `Map` of `Web.Api`'s compiled UrlMap and of each forwarded class. For roles `OcuTalonViewer`, every route whose method is not GET gets 403 `read_only` and `continue` 0, with no submit. `POST /v1/session/end` passes. GET routes pass.
  - With roles `OcuTalonViewer,OcuTalonUser`, nothing is refused.
  - With roles `OcuTalonViewer,OcuTalonAdmin`, `POST /v1/settings/budgets` gets `read_only` and `admin` is false.
  - `Shell.HasRole` admits the viewer and refuses `OcuTalonTraceViewer` alone.
  - `/v1/state`: `viewer`, `admin` and `rolesAssignable` for each role set.
  - The demo-account role set `OcuTalonUser,OcuTalonTraceViewer,OcuTalonApprover` with the demo forced: `admin`, `viewer` and `rolesAssignable` are false, and the Roles routes give `not_admin`.
  - -- AC 2, AC 3, AC 4.
- [x] `Test/Core/AnswersInWebRoles.cls` -- Add `TestDemoApproverOwnSessionOnly`. A fixture user with `DEMOROLES` + fixture `OcuTalonApprover` + the application roles, with `onlineDemo` forced and restored:
  - answers its own session's request (approved);
  - gets `not_visible` for another session's request, which stays pending.
  - It reuses the class's guard and cleanup. -- AC 3.
- [x] `Test/Web/Api.cls:132`, `web/e2e/api/api.spec.ts:135`, `web/e2e/frame/frame.spec.ts:607` -- Add the two new state keys to the key order. -- Shared surface.
- [x] `web/scripts/roles-view.test.mjs` and `web/scripts/viewer-sources.test.mjs` (new), and `web/scripts/ux-strings.test.mjs` -- They cover:
  - `roleOutcome` for each status and reason;
  - the texts equal to PUBLIC TEXT, and to `Web.RoleSettings`' parameters, read from the class source;
  - every guarded component file imports `isViewer`;
  - `isViewer` true only for `viewer: true`.
- [x] `web/e2e/api/roles.spec.ts` (new, chromium; real HTTP) -- It covers:
  - 401 when signed out (GET and POST);
  - the LIVE `OcuTalonUser` fixture gets 403 `not_admin` (GET and POST);
  - the viewer gets 403 `read_only` on `POST /v1/settings/roles` and on every state-changing route of the Matrix table (one request each, then `GET /v1/state` shows its chat unchanged), while `POST /v1/session/end` answers 200;
  - the README admin: GET lists `ZzRoleTarget`; grant `OcuTalonViewer` (`changed` true, then false), GET shows it, remove (`changed` true);
  - each refused role and user of the matrix, and a bad shape, gets 400 with its reason;
  - each test restores the target's roles.
- [x] `web/e2e/settings/roles.spec.ts` (new, sign-in-2) -- It covers:
  - On the real state the Settings nav has no Roles entry.
  - With `/state` stubbed to `rolesAssignable: true` (the 25.3 `changeSnapshot` pattern):
    - the README admin opens Roles, which lists from the real route;
    - by keyboard only, the admin grants `OcuTalonViewer` to `ZzRoleTarget` and sees the step-2 text, then removes it and sees the text again;
    - an unknown user shows PUBLIC TEXT 12a;
    - every control is reached by its label (`getByLabel`/`getByRole` name).
- [x] `web/e2e/sign-in/viewer.spec.ts` (new, chromium) -- `ZzViewer` signs in with the real sign-in and sees no no-role message. It covers:
  - the composer is absent, and the viewer line is shown;
  - with a pending approval card, an incident and demo mode stubbed into the snapshot, Approve, Reject, Dismiss and Break the feed are absent;
  - History and Usage open;
  - there is no Settings link;
  - a `POST /v1/messages` from the page's context gets 403 `read_only`.

- [x] [Ruling] Planner rulings of 2026-11-13 ~18:55Z (`.coordination/prompts/story-254-rulings-20261113.md`, binding; summarized under Design Notes "Planner rulings"). Work them into the tasks above:
  - Row 2 text CHANGED to exactly: "Approvers can answer the approval requests that reach them, for every kind of risky action. Viewers can open OcuTalon but can't chat, answer or change anything." (pin it equal in the page texts and its tests).
  - C1 (critical): `Roles.Refusal` returns `user_system` (checked before `user_managed`) for IRIS's own accounts: `UnknownUser`, `_SYSTEM`, `SuperUser`, `Admin`, `CSPSystem`, `IAM`, `_Ensemble`, `_PUBLIC`, `HS_Services`, compared in lower case, plus any name starting with `_` or `%`. Field text (page and server, new approved PUBLIC TEXT): "This is an IRIS system account, so its roles can't be changed here." Tests: one per name class in `Test.Install.RolesAssign` (`UnknownUser`, `_SYSTEM`, `SuperUser`, a `%x` name), plus a real-HTTP case; `mutation:` line "the user_system check skipped -> red". `Holders` still lists such an account if it already holds an OcuTalon role, with `managed: true`.
  - C2: `Test.Web.ViewerApi` also lists every GET route that writes anything (a row, a global, a command) for a viewer-only caller, other than the viewer's own session or presence row. Task 0 adds (f): find them (read `Web/Api.cls` GET handlers and measure on the throwaway). If ANY exists, HALT `blocked` with blocking condition `intent gap: C2 GET routes that write for a viewer: <list with file:line>` before implementing past Task 0.
  - Task 0 (c) also measures how long a signed-in CSP session can last (the web applications' session timeout, and whether the durable session renews it). If a removed viewer could keep reading for MORE THAN 24 HOURS, HALT `blocked` with `intent gap: C-24h removed viewer session lasts <measured>` before implementing past Task 0. Otherwise row 9's two texts are both approved: the step-2 text, and "Saved. Applies when they next sign in. Recorded in the audit log." for a viewer removal only (if (c) shows the session keeps the role).
  - C3 (report only, no code): record under Design Notes "Measured" whether `Channel.Telegram.In` and the email entry check that the person holds `OcuTalonUser` at USE time (not only at pairing or connection), with file:line. The lead files a DW if they don't.
  - C4: `SecretHandoff` has no TTL on this branch (`Core/SecretHandoff.cls`: Put/Take/Discard only); do NOT widen it. The reverse uri left on a submit timeout is ledgered by the lead (low DW).
  - DW-1282 (standing rule): the Roles section's web code (roles view and its section file) goes in a LAZY chunk (dynamic `import()`), never in the initial bundle; the build's initial-bundle cap (1 MB) must not be exceeded and is never raised. Name the chunk in Verification; if the initial bundle would exceed the cap, HALT `blocked` with `intent gap: DW-1282 initial bundle over cap`.
  - Q8 amendments (applied by the lead in planning artifacts; nothing for the implement stage).
- [x] [Ruling] Task 0 rulings (Contest Planner ~19:40Z, `story-254-rulings-20261113.md` "Task 0 rulings", BINDING; Task 0 is DONE, its measurements stand under Design Notes "Measured"; do not re-run it):
  - C-24h, option (a): `Web.Api` `OnPreDispatch` re-reads the signed-in user's live role set with `$SYSTEM.Security.GetUserRecursedRoleSet($Username)` and ends the CSP session (401 `signed_out`, as an expired session answers) when the user holds neither `OcuTalonViewer` nor `OcuTalonUser`. Conditions: (1) it runs in the REST process as the signed-in user with NO escalation: no grant, no privileged job, no `$Roles` change; if the call needs a privilege the user lacks, HALT `blocked` with `intent gap: C-24h re-read needs a privilege: <evidence>`. (2) If the call returns an error, refuse only that ONE request (401, or the existing failure code) and do NOT end the session. (3) Measure the added cost per request (p95 over at least 200 requests, recorded under Design Notes "Measured"); if p95 is over about 5 ms, add a per-session cache of AT MOST 60 s (keeps "Applies within a minute" true); otherwise no cache. (4) Row 9 is the step-2 text ONLY ("Saved. Applies within a minute. Recorded in the audit log."); drop the conditional "Saved. Applies when they next sign in. ..." text everywhere. Tests: a viewer whose `OcuTalonViewer` is removed gets 401 within 60 s on the same session while it keeps polling; the same for a user whose `OcuTalonUser` is removed; a user holding both roles who loses one is unaffected; `mutation:` "the re-read skipped -> red". These are throwaway-only (they change roles).
  - C2, option (a): `GET /v1/memory/items` (with or without `q`) and `GET /v1/memory/pinned` answer 403 `read_only` to a viewer-only caller, before anything is submitted (no command, no allowance write). `Test.Web.ViewerApi` pins both (status, code, and that nothing was submitted). The viewer page never calls either route (the memory cards are hidden for a viewer; pin it in the web test).
  - C3 (DW-1284) and C4 (DW-1283) are ledgered by the lead; nothing to do here.
- [x] [Review] Planner final ruling 2 (DW-1290; `story-254-rulings-20261113.md` "Final 25.4 rulings before push", BINDING) -- `src/ocutalon/cls/OcuTalon/Web/Api.cls` `OnPreDispatch` / `IsAdmin` and `Web/RoleSettings.cls` `Refusal` -- the C-24h live role re-read (`$SYSTEM.Security.GetUserRecursedRoleSet($Username)`) extends to `OcuTalonAdmin` under C-24h's rules: no escalation (else HALT blocked); an error refuses only that one request, never the session; no cache. Admin checks on `/v1/settings` (and `/v1/state`'s `admin`) read the live set, not the session's `$Roles`. Test (throwaway): remove `OcuTalonAdmin` from a signed-in admin; the next `/v1/settings` request answers 403 `not_admin`; `mutation:` "skip the admin re-read -> red".
- [x] [Review] Planner final ruling 3 (DW-1297, option (a), BINDING) -- `Core/SettingsOps.cls` `SaveRoles`, `Install/Step/Roles.cls` `Assign`, `web/src/app/settings/roles-section.ts` / `roles-view.ts` (lazy chunk only) -- a save that changes nothing (`changed` false: granting a role the user already holds, or removing one they don't hold) writes NO audit entry and shows this new PUBLIC TEXT, word for word: "No change: {user}'s roles are already as you set them." (`{user}` the target user name, rendered as text, never HTML). Tests: both no-op cases, each asserting the text and that no audit entry was written; `mutation:` lines for both (e.g. show the saved text for changed false -> red; write the entry for a no-op -> red).
- [x] [Review] Ruling 1 (veto window) is CLOSED: no veto, viewer wins; the review-time narrowing (a viewer who also holds `OcuTalonAdmin` is refused on `/v1/settings`) stands. The self-lockout refusal is routed to Story 25.5 as DW-1303; nothing for this pass.
- [x] [Review] Constraint: the Roles code stays in its lazy chunk, and the initial bundle must stay at or below 997.59 kB (DW-1282; never raise the cap). Anything outside these three items is out of scope for this pass (a STOP per the ruling).
**Acceptance Criteria:**
- AC 1: Given an admin on a local install with the roles present, when they open Settings › Roles, then the users holding an OcuTalon role are listed with their roles. The admin can grant or remove `OcuTalonApprover` and `OcuTalonViewer` (per-kind roles are shown but are granted in IRIS, by V3). Each change goes through `SettingsOps` to `Roles.Assign`, confirms with "Saved. Applies within a minute. Recorded in the audit log." and writes one `Settings` audit entry. Every other role and every managed account is refused, with its text.
- AC 2: Given a user holding only `OcuTalonViewer`, when they sign in, then the page, History and Usage load read-only: no composer, and no Approve, Reject, Dismiss, Break the feed or other state-changing control. Every state-changing route answers 403 `read_only` and changes nothing; sign-out still works.
- AC 3: Given the online demo, when the demo account (with the fixture `OcuTalonApprover`) signs in, then it gets no settings link and no Roles section, and it answers only its own session's requests.
- AC 4: Given a user without `OcuTalonAdmin`, when they call either Roles route, then the answer is 403 `not_admin`. On the online demo an admin gets 409 `not_available` before the body is read.
- AC 5: Given this branch, where Story 26.4 has not merged (`STEP6ROLES` is absent), when an admin opens Settings, then no Roles entry shows (no half feature).
- AC 6: Given the tests' fixture roles, when each refusal, grant and removal runs, then each refusal changes nothing and writes no entry, each effective change writes exactly one entry, and the section works by keyboard with every control labelled.
- DW-1267: the handoff in both directions, the leak scan, admin-only routes and a test per refusal (addressed by the `RoleSettings`, `SettingsOps` and `RolesApi` tasks above).

### Review Findings

Code review 2026-11-13 (bmad-code-review, full mode; layers blind-hunter, edge-case-hunter, verification-gap and acceptance-auditor, review tier full-opus). 41 raw findings, 16 entries after grouping (high 0, medium 3, low 13), 17 rejected (appendix). Each entry: severity / fix-risk / footprint / disposition.

- [x] [Review][Patch] A viewer who also holds OcuTalonAdmin could still use the settings GETs, among them `GET /v1/settings/roles`, which submits a ListRoles command (ruling C2), while `/v1/state` says `admin: false` [src/ocutalon/cls/OcuTalon/Web/Api.cls OnPreDispatch; src/ocutalon/cls/OcuTalon/Web/RoleSettings.cls Refusal] -- medium / low (two conditions, pinned) / in-story / fixed: the settings admin check treats a viewer (session or live roles) as no admin (403 `not_admin`), and `RoleSettings.Refusal` does too; `ViewerApi.TestViewerAndAdmin` and `RolesApi.TestViewerPostIsReadOnly` pin the three GETs. (blind+edge+verification-gap+auditor)
- [x] [Review][Patch] `viewer.spec.ts` V2's absence checks could not fail: the rail heading is "Heartbeat checklist", not "Heartbeat"; Telegram is in the rail only when included; and Break the feed had no control that its box was mounted [web/e2e/sign-in/viewer.spec.ts V2] -- medium / low / in-story / fixed: the right heading, Telegram stubbed as included, a control that the rail shows "Recent decisions", and a control that the demo guide mounts the Break the feed box; live part 26/30 green. (blind+verification-gap)
- [x] [Review][Patch] The review-pass paths of `SaveRoles` (a Refusal that throws; `online_demo` from Refusal) were untested [src/ocutalon/cls/OcuTalon/Test/Core/SettingsRoles.cls TestRefusalCodes; Test/Core/RolesStub.cls] -- low / low / in-story / fixed: a `throw` mode in `RolesStub`, and cases for `failed` and `not_available` (uri consumed, Assign not called). The inner Try in `SaveRoles` is redundant with `OnMessage`'s catch, so the throw case pins the outcome, not that Try. (blind+verification-gap)
- [x] [Review][Patch] Focus fell to the page after a Remove, because the pressed button leaves with the role [web/src/app/settings/roles-section.ts change] -- low / low / in-story / fixed: the list heading (`tabindex="-1"`) takes focus once the list is drawn again (the Memory card and Documents precedent); one `.focus(` call kept (`focusLater`); RS2 asserts it; live part 17/20 green. (blind)
- [x] [Review][Patch] `roles-section.ts` class doc called the lazy chunk "a deferred block" [web/src/app/settings/roles-section.ts:1-20] -- low / low / in-story / fixed (Rule 14). (blind+auditor)
- [x] [Review][Patch] `LiveRolesApi.NewUser` doc said it adds the application roles [src/ocutalon/cls/OcuTalon/Test/Web/LiveRolesApi.cls NewUser] -- low / low / in-story / fixed. (blind)
- [x] [Review][Patch] `TestHoldersSortIgnoresCase` doc named the fixtures without the class prefix's second A [src/ocutalon/cls/OcuTalon/Test/Install/RolesAssign.cls:19] -- low / low / in-story / fixed. (verification-gap)
- [x] [Review][Patch] `viewer-sources.test.mjs` pinned the header's Settings link with `/admin/`, which any file with the word passes [web/scripts/viewer-sources.test.mjs] -- low / low / in-story / fixed: the `@if (admin())` block and the `admin` computed are matched. (blind+verification-gap)
- [x] [Review][Patch] `TestHolders`' "fixture users come in name order" read the test's own local array [src/ocutalon/cls/OcuTalon/Test/Install/RolesAssign.cls TestHolders] -- low / low / in-story / fixed: it compares the two users' indexes in `Holders`' list. (verification-gap)
- [x] [Review][Patch] `TestAuditFailurePutsTheRoleBack` did not check the real grant that its removal half needs [src/ocutalon/cls/OcuTalon/Test/Install/RolesAssign.cls] -- low / low / in-story / fixed: `AssertStatusOK` on it. (blind)
- [x] [Review][Patch] `RoleSettings.List` submitted ListRoles without the CSP session's SessionRef, so its trace was not filed under the admin's session (AD-26), unlike `Save` and `HookSettings` [src/ocutalon/cls/OcuTalon/Web/RoleSettings.cls List] -- low / low / in-story / fixed. (auditor)
- [x] [Review][Patch] Ruling C2's test did not pin the 403 status of the memory GETs [src/ocutalon/cls/OcuTalon/Test/Web/ViewerApi.cls TestMemoryReadsRefuseAViewer] -- low / low / in-story / fixed: `PreDispatch` keeps the response status and the test asserts "403 Forbidden"; nothing is submitted because the dispatch stops (continue 0) before any route runs. (auditor)
- [x] [Review][Patch] AC 3's test gave both fixture requests `RequiredRole` OcuTalonUser, so the fixture `OcuTalonApprover` played no part [src/ocutalon/cls/OcuTalon/Test/Core/AnswersInWebRoles.cls TestDemoApproverOwnSessionOnly] -- low / low / in-story / fixed: both rows require OcuTalonApprover, so the own-session answer needs the fixture role. (auditor)
- [x] [Review][Defer] Settings > Roles shows "Saved. Applies within a minute. Recorded in the audit log." for a save that changed nothing (changed false), though no entry is written [web/src/app/settings/roles-section.ts change] -- deferred: DW-1297, medium / low / in-story / decision-pending owner=burndown: the fix needs new public text (a no-change text) or a product call to show nothing, both owner-only. (edge)
- [x] [Review][Defer] Viewer guards in 9 of 14 components are pinned only by source regexes [web/scripts/viewer-sources.test.mjs] -- deferred: DW-1298, low / med / in-story / wontfix-accepted, reopen_if in the ledger; the server's 403 is pinned. (verification-gap)
- [x] [Review][Defer] POST `/v1/settings/roles` checks only the body's types before the handoff, against Planner Gate SECURITY row 2's value list [src/ocutalon/cls/OcuTalon/Web/RoleSettings.cls ShapeFields] -- deferred: DW-1299, low / low / in-story / by-design (frozen I/O matrix rows and Decided in-stage 5; the client's answers are the matrix's, and Assign refuses before any change). (auditor)

Rejected:
- `false` Edge: `LiveRoles` would sign out a user whose OcuTalonUser comes from a web application's roles -- `/ocutalon` and `/ocutalon/api` grant only `%DB_*` roles (`Install/Step/Web.cls:49,195,204`); OcuTalonUser is only on the user record.
- `false` Edge: `TestChangesShape`'s consumed check is vacuous for `{"other": uri}` -- the assertion pins the `{"handoff": uri, "x": 1}` case, which consumes the uri; a uri under another key is not the save's, and the route discards its own on every path.
- `false` Edge: an unprivileged caller of `Refusal` learns which users exist -- `UserKnown` enters `%SYS`, which throws `<PROTECT>` without `%Admin_Secure` (Decided in-stage 2, `TestNoPrivilege`); only the constant managed and system names answer before it.
- `false` Edge: `TestNoPrivilege` misses unknown or marked targets -- both reach `UserKnown` and the same `<PROTECT>` path.
- `false` Verification-gap: deleting `SaveRoles`' Try lets a thrown error escape `OnMessage` -- `SettingsOps.OnMessage` catches every exception as `failed` (observed: the mutation stayed green).
- `false` Verification-gap: ACs without a mutation line -- each AC has one recorded (Rule 19 is one per AC).
- `false` Verification-gap: `ViewerApi`'s "the GET route that writes is among them" cannot fail on a product change -- it is a fixture-integrity check of the class's own lists, as its message says.
- `false` Blind: the Auto Run Result's 997.59 kB disagrees with the Measured 997.54 kB -- two builds (before and after the review pass's phone guard); this review's build measures 997.59 kB again.
- `low` Blind+Edge: `Holders` and `Switch` read only directly granted roles, so a role held through another role is not listed -- a nested OcuTalon role is not a configuration this product makes; a recursive read adds complexity.
- `low` Blind: `Refusal` should check the privilege first -- Decided in-stage 2; the only answers before the privilege error are constant names.
- `low` Blind: `TestRoleCalls` asserts only "not 5003" for `Holders` -- the task text's exact wording; the test job's privileges are the runner's.
- `low` Edge: `Audit` throwing would leave the change without a put-back -- `Bridge.Audit.Record` returns a status on every refusal; a throw from `%SYS.Audit` in `SettingsOps`' `%All` job is not a path seen here.
- `low` Edge: two concurrent `Assign` calls for one user -- needs two admins on one user at the same instant on a local install.
- `low` Edge: `Listing` ignores a `Next` failure partway -- no realistic trigger for a `%SYS` query over `Security.Users`.
- `low` Verification-gap: `Web.Api.RolesInstalled` is never run true -- Story 26.4's `STEP6ROLES` flips `settings/roles.spec.ts` RS1, which reads the real `/v1/state`.
- `low` Verification-gap: `RolesApi.TestRefusals`, `api/roles.spec.ts` R5 and RS2 leave a system account changed when the `user_system` check is broken -- `RolesAssign.TestSystemUserRefused` catches and repairs that defect, and each run is a throwaway.
- `low` Verification-gap: `TestUserNameNeverStored` scans every roles row on the stack -- every real row passes through the route, which takes or discards its uri; a leftover is the defect it guards.
- `low` Verification-gap: the Roles section's load-failure, denied and off states have no rendered test -- `roleOutcome` is unit-tested; the section is admin-only and hidden until Story 26.4.

## Spec Change Log

- 2026-11-14 ~00:00Z, lead: rework iteration 1 (trigger: Planner final rulings before push, cap_override-free; items DW-1290, DW-1297): re-opened `done` -> `in-progress`; `[Review]` items above; DW-1303 routed to 25.5.

- 2026-11-13 ~19:40Z, lead: Planner Task 0 rulings: C-24h option (a) with four conditions (no escalation; an error refuses one request only; p95 > ~5 ms allows a <= 60 s per-session cache; row 9 = step-2 text only), C2 option (a) (both memory GETs 403 read_only for a viewer, nothing submitted). Worked into Tasks & Acceptance as the second `[Ruling]` item; status reset blocked -> in-progress (re-dispatch protocol); implement pass 2.

- 2026-11-13 ~19:10Z, lead: Contest Planner rulings on the Planner Gate (`story-254-rulings-20261113.md`): APPROVED with row 2 changed, row 9 both texts (conditional on Task 0 (c) and the 24-hour STOP), new `user_system` text (C1), C2 STOP condition, C3 report, C4 DW, Q1-Q8 approved, footprint extension into `Install/Step/Roles.cls` granted. Standing DW-1282: lazy chunk. Worked into Tasks & Acceptance as the `[Ruling]` item; Planner Gate row 2 and row 12 updated.

## Review Triage Log

### 2026-11-13 - Review pass
- verdicts: 30 rows for the 37 findings the layers reported (a defect that two layers reported shares one row) - high 0, medium 7, low 17, false 6, maybe-false 0
- findings:
  - `[medium]` `[patch]` Blind: the simulated phone shows Approve and Reject to a viewer (`phone/phone-request.ts`), and Edge: the same, plus handlers not guarded -- real (demo mode on); `isViewer` guard added, `phone/phone-request.ts` joined `GUARDED`, `phone-request-sources.test.mjs` updated; the handlers are reached only through the hidden buttons and the server refuses with 403, so no handler guard (rejected).
  - `[low]` `[patch]` Blind: the `MESSAGENOTADMIN` doc comment sits on `MESSAGEREADONLY` -- real; the parameter moved above it.
  - `[low]` `[patch]` Blind: "a role that an admin removed stops applying" over-claims (the admin role is read from the session) -- real; Api doc and spine sentence narrowed to the two roles; the admin case is deferred (below).
  - `[low]` `[patch]` Blind and Edge: `Assign` ignores the put-back's status -- real but needs two failures; the error is appended to the audit error.
  - `[low]` `[patch]` Blind and Edge: `SettingsOps.SaveRoles` calls `Refusal` without a Try -- real after the handoff is taken; a thrown error is now `failed`.
  - `[medium]` `[patch]` Blind and VG: `Holders` `managed` for a system-named account unpinned and the test header claims it -- real; `TestHoldersListsSystemAccountAsManaged` added, header corrected, mutation line written.
  - `[medium]` `[patch]` Edge and VG: `/v1/state` `viewer` and `admin` read the session's roles while `OnPreDispatch` also uses the live roles -- real (a user cut down to the viewer role sees controls that answer 403); `StateBody` reads the live roles too, `TestStateFollowsLiveRoles` and its mutation added.
  - `[medium]` `[patch]` VG: nothing pins that the CSP session ends after the live re-read's 401 -- real (the second 401 would come back anyway); `ViewerApi` asserts `EndSession` on both paths and `LiveRolesApi` gives the role back and still expects 401; mutation line written.
  - `[medium]` `[patch]` VG: `RoleSettings` outcome mapping (List 500 on fail and throw, 501 `not_built` for List and Save) untested -- real; `TestListAndSaveOutcomes` and a `notbuilt` probe mode added, mutation line written.
  - `[medium]` `[patch]` VG (Rule 19): assertions that cannot fail (`IsObject(users)` after `users = []`, `users.%Size() = 0` on the demo refusal, a probe counter that the test never reaches) and a count that leftovers satisfy (`lists >= 1`) -- real; the first three removed, the count compared with its value before the test.
  - `[low]` `[patch]` Blind: the spine's "p95 under 0.1 ms measured" is not backed by a recorded figure -- the measured 0.066 ms over 250 calls is now the stated figure.
  - `[low]` `[defer]` Edge: a user name ending in a sensitive suffix makes `Audit.Record` redact the roles in the entry -- real, rare, and the `roles.<user>` setting is pinned by the Matrix; deferred.
  - `[medium]` `[defer]` Blind: a removed OcuTalonAdmin keeps applying until the session ends -- pre-existing behaviour of the admin check, outside ruling C-24h; deferred.
  - `[false]` `[reject]` Edge: `ViewerMay` lets a trailing-slash variant of `/v1/memory/items` through -- `%CSP.REST` matches a route's regular expression against the whole URL, so the variant matches no route (the case variants are pinned in `TestMemoryReadsRefuseAViewer`).
  - `[false]` `[reject]` VG: viewer guards "have no running test" and a bypass keeps the regexes green -- `viewer-sources.test.mjs` pins each guarded template's `@if (!viewer())` structure, so `@if (true)` fails it; the rendered controls of the four AC names run in `viewer.spec.ts`.
  - `[false]` `[reject]` Edge: `LiveRoles` would sign out an externally authenticated user with no stored roles -- ruling C-24h fixed the call; OcuTalon signs in by password against IRIS users.
  - `[false]` `[reject]` Edge: the Roles routes accept an empty or 161-character `user` before a handoff, against the task text -- the frozen I/O matrix says 400 `user_unknown` for both; the matrix wins (two rows: ShapeFields and its claim).
  - `[false]` `[reject]` Edge: `List` leaves a handoff when `Data` has none -- SettingsOps is the only producer and always sets it.
  - `[low]` `[reject]` Blind: `SaveRoles` reuses `MESSAGEWEBHOOKSAVED` and the text says "Applies within a minute" -- the text is ruled (PUBLIC TEXT 9); only the constant's name is off.
  - `[low]` `[reject]` Blind: tests fail when Story 26.4 lands -- by design: the tripwires are named under Consumed-by.
  - `[low]` `[reject]` Blind: `LiveRolesApi` hard-codes port 52773 and the namespace -- the test runs inside the throwaway, where that is the web port.
  - `[low]` `[reject]` Blind: `viewer-sources.test.mjs` is regexes over template text -- the project's pattern for web sources; rendered evidence is `viewer.spec.ts`.
  - `[low]` `[reject]` Edge: `Switch` leaves a change unreverted when the re-read fails after it -- theoretical (`wontfix-theoretical`: the re-read of a user just changed).
  - `[low]` `[reject]` Edge: `roleOutcome` shows `denied` for a viewer-admin's 403 `read_only` -- unreachable: `admin` is false for a viewer, so the section is never shown.
  - `[low]` `[reject]` Edge: two overlapping loads in the Roles section -- every change disables its button while it runs; not worth the code.
  - `[low]` `[reject]` Edge: the lazy chunk fails to load -- a deploy race on an admin-only page; not worth the code.
  - `[low]` `[reject]` Edge: a deep link to Roles before the snapshot arrives shows Models first -- the page needs the snapshot's `admin` for every section.
  - `[false]` `[reject]` VG: acceptance criteria without a mutation line -- one mutation per AC is recorded (Rule 19); the rows named are second halves.
  - `[low]` `[reject]` VG: `TestDemoApproverOwnSessionOnly` is unmutated -- it pins `Approval.Answer`'s own rule, which this story does not change.
  - `[low]` `[reject]` Intent: the Roles routes are not gated by `RolesReady()` -- the flag gates the section, as the intent says; the routes are admin-only and `Assign` refuses an unknown role by name.

### 2026-11-13 -- Review pass (rework iteration 1, follow-up pass)
- verdicts: 24 findings -- high 0, medium 0, low 16, false 8, maybe-false 0
- findings:
  - `[low]` `[patch]` Blind 1: the `Api.cls` header still said the settings check reads `$Roles` -- fixed: the line names the user's live roles (IsAdmin); comment only.
  - `[low]` `[reject]` Blind 2: spec text (lines 460, 619, AC 1) still describes the old behaviour -- the fix is to edit this build's spec.
  - `[low]` `[reject]` Blind 3: a second live read failing after `OnPreDispatch`'s first one succeeded gives 403 not_admin, not 500 -- fails closed for that one request, keeps the session, needs two failures in one request; one read per request would add a parameter to `IsAdmin` and its overrides.
  - `[low]` `[reject]` Blind 4: several live reads per request, cost not re-measured -- each is the measured 0.066 ms (the ruling: the measurement stands), about 0.2 ms per request; a one-read cache is what C-24h forbids.
  - `[false]` `[reject]` Blind 5: `review_loop_iteration` and `followup_review_recommended` not updated -- set at finalize.
  - `[low]` `[reject]` Blind 6: `TestRemovedAdminLosesSettings` checks GETs only -- a POST takes the same `OnPreDispatch` admin check, and `TestRemovedAdminIsRefused` pins the Save route's refusal.
  - `[false]` `[reject]` Blind 7: `TestNoChangeWritesNoEntry` leaves state behind and could miss an extra entry -- its `NewTarget` fixtures are removed by the class's cleanup, and an extra entry in the middle changes the asserted `to` order.
  - `[false]` `[reject]` Blind 8: the date in `ux-strings.test.mjs` is wrong -- the rulings file's own heading dates the ruling 00:05Z Nov 14.
  - `[low]` `[reject]` Blind 9: the section's saved line is pinned by source regexes -- RS3 renders it in Chromium, and the regexes bar `innerHTML`; a rendered component test needs a fresh stack and a bundle per run.
  - `[low]` `[reject]` Edge 1: same as Blind 3.
  - `[low]` `[reject]` Edge 2: a failed live read inside `/v1/state` or a route's `Refusal` shows no admin or 403 -- the same double-failure window as Blind 3; `OnPreDispatch` answers 500 first for the same request.
  - `[low]` `[reject]` Edge 3: same as Blind 4.
  - `[low]` `[reject]` Edge 4: the unit test asserts no text -- the spec's tiers are met: the server tests assert no entry, RS3 and the `saveLine` tests assert the text.
  - `[low]` `[reject]` Edge 5: the line names the user as typed, not a canonical name -- a canonical name needs a new response field (an API shape change); `{user}` is the target the admin named.
  - `[false]` `[reject]` Edge 6: condition (2) holds only for `OnPreDispatch` -- `IsAdmin` answering 0 for one call ends no session and refuses or shows no admin only for that request, which is the condition.
  - `[low]` `[reject]` VG 1: "drawn as text, never HTML" pinned only by source regexes -- same as Blind 9; Angular interpolation escapes.
  - `[low]` `[patch]` VG 2: no observed mutation for the fail-closed read and the no-cache conditions -- both run: `IsAdmin` answering 1 on a failed read -> `ViewerApi` `TestAdminFollowsLiveRoles` red; `IsAdmin` caching in the session -> `LiveRolesApi` `TestRemovedAdminLosesSettings` red; both reverted byte-identical; lines in Verification.
  - `[low]` `[reject]` VG 3: `TestRemovedAdminIsRefused`' route half skips when `Missing` is set -- the same guard as its sibling `TestNotAdmin`; the real-HTTP test and the `Guard`-based `TestNoChangeWritesNoEntry` fail loudly there.
  - `[low]` `[reject]` VG 4: same as Blind 4.
  - `[low]` `[reject]` VG 5: no `liveError` seam in `RoleSettingsProbe` for the route-level read failure -- same window as Blind 3.
  - `[false]` `[reject]` VG 6: `SessionEvents.OnLogin` reads `$Roles` -- it records the sign-in flag, not an admin gate, and is outside this pass.
  - `[false]` `[reject]` Intent 1: admin-only wording versus the live read -- descriptive; the live read is the ruled reading.
  - `[false]` `[reject]` Intent 2: the no-op rule lives at `Assign` and the diff changes the page text only -- descriptive; the rule already held and tests pin it.
  - `[false]` `[reject]` Intent 3: session-roles reads remain outside the diff -- the same `OnLogin` read as VG 6; no admin gate reads `$Roles` now.

## Design Notes

**Planner rulings (2026-11-13 ~18:55Z, binding; `.coordination/prompts/story-254-rulings-20261113.md`).** APPROVED with two text changes (row 2 reworded; new `user_system` text) and four security conditions: C1 refuse IRIS system accounts (`user_system`, one test per name class, mutation); C2 any GET route that writes for a viewer-only caller is a STOP; C3 report the Telegram/email use-time `OcuTalonUser` check (DW if absent; not blocking); C4 no TTL in SecretHandoff, so a low DW, SecretHandoff not widened. Task 0 (c): a removed viewer able to keep reading > 24 h is a STOP. Q1 (a), Q2 both texts, Q3 yes, Q4 yes, Q5 (a), Q6 one entry, Q7 approved (pinned additive contract; footprint extension into Lane A `Install/Step/Roles.cls` granted by the orchestrator), Q8 approved (spine replacements, epics.md AC 1, and EXPERIENCE.md:1143 changed to row 2's second sentence). Standing rule DW-1282: new web code in lazy chunks; exceeding the initial-bundle cap is a STOP. Push only after the 1.0.9 CI HOLD lifts (1.0.10).

**Architecture decisions (Rule 6):**
- AD-1: commands are production messages; `ListRoles` is a read verb through `CommandsIn`.
- AD-3: only Lane A's installer area switches to `%SYS`. `Assign`/`Holders` do; the REST process and `SettingsOps` never do.
- AD-4: no personal data in production messages, and session ownership on the demo.
- AD-11: approver roles; `MayAnswer` is unchanged.
- AD-13: the post-sign-in check, `OnPreDispatch` order, settings routes admin-only, the envelope.
- AD-17: one audit writer; V4's narrowing lets the role change's IRIS entry hold user names.
- AD-19: `SettingsOps` the only settings writer, `SecretHandoff`.
- AD-24: the roles, the S2 allowlist and refusals, V3.
- AD-25: the demo proxy is unchanged.
- AD-29: lanes and footprint; see "Footprint" below.
- AD-33: the rows land in the same change.
- AC 1's "any `OcuTalonApprover_<kind>`" contradicts AD-24's V3 rule ("The per-kind roles are not assignable through it"). The binding Planner ruling V3 already decides this, so the plan follows AD-24, and the lead amends the AC text (Amendments, below). No other AC contradicts an AD.

**Rule 1/2.**
- Integration AC: the page's Roles section (e2e `settings/roles.spec.ts`) and the real-HTTP spec read the real `Web.RoleSettings` → `SettingsOps` → `Roles.Assign`/`Holders` and observe the grant in the next list. `Test.Web.RolesApi` observes the role set and the audit entry.
- Consumed-by: Story 26.4, which creates the roles and adds `Parameter STEP6ROLES = 1;` to `Install.Step.Roles` in the same change, flipping `rolesAssignable` and the two tripwires (`RolesApi` "RolesReady is 0 on this branch", `settings/roles.spec.ts` "no Roles entry on the real state"). Also Story 25.5, which may read `viewer` to show its can't-answer text.
- Consumes:
  - `SecretHandoff` (Stories 35.3 and 21.2), `Bridge.Audit.Record`, `CommandsIn`.
  - `Users.#SERVICEUSER`/`#MARKER`, `Approval.#WORKFLOWUSER`, `Data.Public.Settings`.
  - The test helpers `Test.Core.SecretHandoff` `Leaks`/`TableHolds`, `AnswersInWebRoles` `Reason`/`CreateUser`, `ApiProbe`, and `live_fixture_user`.
- Extend, don't copy:
  - `Web.RoleSettings` follows `Web.HookSettings` (a forwarded class, `Refusal`, the Hand pattern) and does not copy it into `Api.cls`.
  - `Roles.Assign` follows `Install.Step.Mcp.Grant`/`Revoke`.
  - `RolesReady(class)` follows `Core.Files.Readable(readerClass)`.
  - `viewer-view.ts` follows `shared/demo-view.ts`.
  - The section follows `webhooks-section.ts`/`webhooks-view.ts`.
  - The leak scan reuses `Test.Core.SecretHandoff`'s helpers.
  - The new test classes extend the probes `ApiProbe`/`HookSettingsProbe`.
  - `TestDemoApproverOwnSessionOnly` extends `AnswersInWebRoles`.

**Ledger inbox:** DW-1267 is addressed by the `RoleSettings`, `SettingsOps`, `RolesApi` and `RolesAssign` tasks, and by AC 4.

**AC evidence already met:** none.
- The prerequisites are built: the settings routes' admin gate (`Api.cls:319-322`), `SecretHandoff`, the forwarded-class pattern, the stub signatures and their pins (Story 37.1), and the `no_role` refusal.
- The web applications already grant a viewer the database roles: `Install/Step/Web.cls:49` `APPLICATIONROLES` starts with `:`, so they apply to every signed-in user (inference from IRIS's `MatchRoles` form; Task 0 (c) and the viewer e2e confirm it). So no grant change is needed, and none is made.
- Write access through those application roles exists for any signed-in user. A viewer's read-only state is therefore enforced in code (`OnPreDispatch`), not by roles.

**Footprint (Rule 11; the lead's dispatch).** This story builds the bodies of Lane A's `Install.Step.Roles.Assign` and `Holders`, adds `Refusal`, and edits Lane A's tests `Test/Bridge/Api.cls` and `Test/Contract/Ac.cls`, plus a new `Test/Install/RolesAssign.cls`. These are a footprint extension into Lane A's files, by the dispatch. The roles, resources, grants, `DEMOROLES` and the README account's grant stay Story 26.4's.

**Contended hunks** (each additive; nothing else in these files changes):
- `Web/Api.cls`:
  - (1) One `<Map Prefix="/v1/settings/roles" Forward="OcuTalon.Web.RoleSettings"/>` line after :296.
  - (2) In `OnPreDispatch`, a 4-line viewer block after :318.
  - (3) One parameter, `MESSAGEREADONLY`.
  - (4) Two private methods, `ViewerOnly` and `ViewerMay`, after `IsAdmin` (:348).
  - (5) In `StateBody`, the `admin` line :1292 gains `&& '..ViewerOnly()`, and two `%Set` lines follow :1295.
  - (6) Doc lines in the class description: the viewer refusal, the Roles routes and the two state keys.
- `Core/SettingsOps.cls`:
  - (1) One `Carry` line for `ListRoles`.
  - (2) One `Save` line for kind `roles`, after :1015.
  - (3) One `XData Sections` row, `{"slug": "roles", "kind": "roles", "fields": []}`.
  - (4) A one-name append to `Values`' skip condition at :943: `|| (section.kind = "roles")`.
  - (5) A new methods block at the end: `ListRoles`, `SaveRoles`.
  - (6) Class-doc lines.
- `web/src/app/settings/**`:
  - `settings-view.ts`: one `SETTINGS_SECTIONS` entry, one label and the "seven sections" comment.
  - `settings-page.ts`: the nav filter and one `@case`.
  - New files: `roles-section.ts` and `roles-view.ts`.
- `Core/CommandsIn.cls` (not contended): one Routes row and one doc line.

**Spine edits.**
- Additive rows that the implement stage adds, marked `[ADDED <date>, Story 25.4]`:
  - REST surface: `GET`/`POST /api/v1/settings/roles`, and `/v1/state` from step 6 with `viewer` and `rolesAssignable`.
  - Ownership: `OcuTalon.Msg.Command.ListRoles` (B), `Web.RoleSettings` and the Settings > Roles section (B), `Install.Step.Roles.STEP6ROLES` (A, Story 26.4).
  - AD-13: the viewer bullet.
- Replacements of Story 37.1's sentences, which the lead applies after the gate:
  - AD-24 S2, "Until Story 26.4 both are stubs (Story 37.1): `Assign` answers "not implemented" (5003) and changes nothing, and `Holders` answers 5003 and `[]`." → "Story 25.4 builds both (Lane B, by the lead's dispatch, in Lane A's file); Story 26.4 creates the roles they assign."
  - "Story 26.4 has a test for each refusal." → "Story 25.4 has a test for each refusal (`Test.Install.RolesAssign`)."
  - "Every assignment and every removal writes an IRIS audit entry (Story 26.4)." → "Every assignment and every removal writes one IRIS audit entry of type `Settings` (setting `roles.<userName>`, from and to the user's OcuTalon roles, naming the acting admin), and no entry when nothing changes (Story 25.4)."
  - `Holders`' "as `{user, roles}`" → "as `{user, roles, managed}`".
  - `Assign` gains the trailing arguments `actingUser, sessionRef, channel` and the sibling `Refusal(userName, role)`.
  - Cross-lane row :1614: "Story 37.1 (stubs), Story 26.4" → "Story 37.1 (stubs), Story 25.4 (bodies), Story 26.4 (roles)".

**Amendments for the lead (epics.md, Rule 5; decided by V3):**
- AC 1 "lets the admin grant or remove `OcuTalonApprover`, any `OcuTalonApprover_<kind>` or `OcuTalonViewer` ... which calls Lane A's role-assignment method (Story 26.4 ...; a stub until it merges)" → "lets the admin grant or remove `OcuTalonApprover` or `OcuTalonViewer`, and shows the `OcuTalonApprover_<kind>` roles each user holds, which an administrator grants in IRIS (Planner ruling V3), through `SettingsOps`, which calls the role-assignment method that this story builds in Lane A's file (the lead's dispatch)".

**Decided in-stage:**
1. The routes live in a forwarded class, `Web.RoleSettings`, which keeps `Api.cls`'s contended hunks to one line, following HookSettings.
2. `ListRoles` is a new read verb rather than a `SaveSettings` read. A save is never a read.
3. `Assign` writes the one audit entry. It changes first and puts the change back if the entry fails, so no change is left without an entry and no entry describes a change that did not happen.
4. Role names are compared without regard to case. The allowlist's spelling is what gets written.
5. User names are capped at 160 characters (IRIS's limit).
6. The viewer refusal code is `read_only`. It runs after the role check and before the admin check, so a viewer-only admin cannot write settings, and `admin` reads false for that user.
7. The viewer UI hides every state-changing control, not only the AC's four (UX: "Viewers see everything read-only"). The Telegram, persona, heartbeat and memory rail cards are hidden, because they are a person's own features.
8. The page posts no guide markers for a viewer.
9. Removal has no confirmation dialog. The AC's confirmation is the saved text afterwards, as on every settings section.
10. The demo's 409 and the demo-account pins are class-level (25.3 decided 12). No `live:online-demo` run is added.
11. The leak scan runs in the IRIS class against the real production (HookSettingsApi precedent). The real-HTTP spec covers the statuses.
12. `new_units: none`. `ci_groups`:
    - `shards` (lane-a `@Install`: `Test.Install.RolesAssign`);
    - `image` (lane-b `@Core`: `Test.Core.SettingsRoles`);
    - `shards-6` (lane-b rest: `Test.Web.RolesApi`, `Test.Web.ViewerApi`, and `Test.Web.LiveRolesApi`, which the C-24h ruling added; the probes `RoleSettingsProbe`, `RolesReadyProbe`, `Test.Core.RolesStub`, `Test.Core.SettingsRolesProbe` and `Test.Install.ZzRolesAuditFails` are not test classes);
    - `shards-2` (lane-a rest: `Test.Bridge.Api`; the Contract class runs in lane-b `@Contract` in `image`);
    - `shards-10` (`live:sign-in`: `api/roles.spec.ts`, `sign-in/viewer.spec.ts`);
    - `shards-4` (`live:sign-in-2`: `settings/roles.spec.ts`).
    - `AnswersInWebRoles` stays in its current shard. No class joins `production`, `browser`, `install-fresh` or `install-upgrade`.

**Measured (plan stage, slot A, read-only):**
- `SecretHandoff` `Put`/`Take` in one process carries 65,536, 1,048,576 and 3,600,000 characters. So no list cap is needed; the cross-process direction is Task 0 (e).
- On slot A, `Security.Users:List("*","*")` answers 10 rows, and slot A has no OcuTalon role (it runs no installer).
- Everything about other platform behaviour is Task 0 and is labelled (inference) until then.

**Measured (Task 0, implement stage 2026-11-13, a warm throwaway of tag `e25s4iw`, build 154, fresh install with the production running; no product code changed yet; scratch probe classes `E25T0.*` loaded on the throwaway only):**
- (a) A probe business operation added to `OcuTalon.Production` (so it runs in an item's job, as `SettingsOps` does) ran `Security.Users.AddRoles`/`RemoveRoles` on a fixture user holding `OcuTalonUser`, in `%SYS`: `before=OcuTalonUser`, `AddRoles OcuTalonViewer` gave `OcuTalonUser,OcuTalonViewer`, `RemoveRoles OcuTalonViewer` gave `OcuTalonUser` again. Each call changed only the named role; both statuses OK.
- (b) The item's job reads `_Ensemble | roles=%All,%DB_OCUTALON_CODE,%DB_OCUTALON_DATA,%EnsRole_ProdPrivs_OCUTALON | %Admin_Secure:USE=1`. A job that logged in with `$SYSTEM.Security.Login` as a fixture user holding `OcuTalonAdmin,OcuTalonUser,OcuTalonViewer` reads `%Admin_Secure:USE=0` (the user's roles hold no `%Admin_Secure`). So `Assign`/`Holders` need `SettingsOps`' job and the check refuses an admin's own CSP job.
- (c) The web applications `/ocutalon` and `/ocutalon/api` have `Timeout=28800` (8 hours of idleness), `UseCookies=2`, `SessionScope=2`, group `OcuTalon`. A fixture user signed in over HTTP (GET the sign-in page, POST `IRISUsername`/`IRISPassword`/`IRISLogin`) got `GET /ocutalon/api/v1/state` 200. The role `OcuTalonUser` was removed with `Security.Users.RemoveRoles` (the user's `Roles` then read empty), and the same session still answered 200 on the very next request, so the CSP session keeps `$Roles` from sign-in. With both applications' `Timeout` set to 20 on the throwaway (restored to 28800 afterwards), eight polls 8 seconds apart (64 s, over three times the timeout) all answered 200, and a request after 30 s of silence answered 401 `signed_out`: every request renews the idle timeout. `OcuTalonUser` stood in for `OcuTalonViewer` because `Shell.HasRole` does not yet admit a viewer; the mechanism (`$Roles` of the session) is the one the viewer check reads. The page polls `GET /v1/events` while it is open, and the idle cap (`idleSeconds`) exists only on the online demo (`Api.StateBody`: `If body.onlineDemo Set body.idleSeconds = ...`). So a removed viewer who keeps a tab open keeps reading with no upper bound (more than 24 hours), and one who closes the tab keeps it for up to 8 hours.
- (d) `Bridge.Audit.Record("Settings", {setting "roles.ZzT0c", from, to, irisUser, sessionRef "", channel "web"})` is OK, and `Test.Bridge.AuditLog.Wait` (10 s default) read it back after 0.26 s. The entry's data holds the target user name and the role lists as written.
- (e) The probe operation (production job) put a 3,000,010-character string with `SecretHandoff.Put` and a separate terminal process took all of it (`length=3000010`, 0.011 s); a second take answered an error. Cross-process works to 3 MB, and a uri is single-use.
- (f) / C2, GET routes that write for a viewer-only caller. Reading every GET handler of `Web.Api`, `Web.Documents`, `Web.History` and `Web.Usage` and diffing `^OcuTalon*`, `^Ens.MessageHeaderD`, `^Ens.MessageBodyD` and `^Ens.Util.LogD` around each GET as a signed-in fixture user (a control of eight idle dumps shows background writes to `^Ens.MessageHeaderD`/`^Ens.MessageBodyD` about every minute and to `^OcuTalonP.StatusMarkD`, so those two are not the routes'):
  - Only the session attach writes on first contact (`Data.Ownership.SessionRef` -> `Attach`, the caller's own session row), and that is the exception C2 names.
  - `GET /v1/memory/items?q=<text>` (`Web/Api.cls:1985` -> `SearchMemories` :2083-2089 -> `SubmitMemory` :2174) submits a `SearchMemory` command through the production. On the online demo `Core/CommandsIn.cls:196-198` makes it consume one message of the session's allowance (`Core/Allowance.cls:63` `TryConsumeRead`), which writes an allowance entry.
  - `GET /v1/memory/pinned` (`Web/Api.cls:2002` -> `ReadPinned` :2024) submits a `ListPinnedMemories` command through the production.
  - Every other GET (`/v1/state`, `/v1/events`, `/v1/persona`, `/v1/heartbeat`, `/v1/memory/precedents`, `/v1/memory/notes`, `/v1/memory/items` with no `q`, `/v1/documents`, `/v1/documents/:ref`, `/v1/history/decisions`, `/v1/history/incidents`, `/v1/usage`) changed no `^OcuTalon*` global beyond the background mark above. `/v1/settings` (GET) is read-only code (`SettingsOps.Values`).
- C3 (report only). Neither `Channel.Telegram.In` (`Channel/Telegram/In.cls:184` `OnProcessInput`, `Run` :204, `Poll` :256) nor the email entry (`Channel/Email/In.cls:37` `OnProcessInput`: owner from the product key `email.owner`, then `Send` to the Item target) mentions `OcuTalonUser`, `$Roles` or `GetUserRecursedRoleSet` anywhere under `Channel/Telegram` or `Channel/Email`. So a message is taken in on the strength of the pairing (Telegram) or the saved mailbox (email), not of the person's role at USE time. What does re-check at USE time is the approval answer: `Bridge/Approval.cls:325` and :412 (`Answer` reads `$SYSTEM.Security.GetUserRecursedRoleSet(irisUser)` under the row's lock). The lead files a DW for the two entries.

**Measured (C-24h, implement pass 2, 2026-11-13, a warm throwaway of tag `e25s4jw`):**
- The re-read, `$SYSTEM.Security.GetUserRecursedRoleSet($Username, .roles)`, runs in a job that logged in (`$SYSTEM.Security.Login`) as a fixture user holding `OcuTalonUser` and the web applications' database roles and no `%Admin_Secure:USE` (the job's `$SYSTEM.Security.Check("%Admin_Secure","USE")` read 0): the status is OK and the roles are the user's. So it needs no privilege, no grant and no privileged job (condition 1).
- Added cost per request, 250 calls in that job (`Test.Web.LiveRolesApi.TestRereadCostIsSmall`): p95 0.066 ms, median 0.056 ms, max 0.204 ms. That is far under 5 ms, so there is no per-session cache (condition 3); every request re-reads, so a removal applies at the very next request.
- Over real HTTP against the throwaway's own web server (`TestRemovedViewerEndsItsSession`, `TestRemovedUserEndsItsSession`): a signed-in viewer (or user) has its role removed with `Security.Users.RemoveRoles`; its next request on the same CSP session is 401 `signed_out`, and the one after it too (the session is over). A user who holds both roles and loses one still answers 200.
- Web bundle (`npm --prefix web run build`): the baseline `HEAD` build has an initial total of 991.99 kB (cap 1 MB). With the Roles section's code in a deferred `@defer` block the first build was 1.01 MB (the first `@defer` in the app brings Angular's defer runtime) and over the cap; with `NgComponentOutlet` it was 999.88 kB; with a `ViewContainerRef` and a dynamic `import('./roles-section')` in `settings-page.ts` it is 997.54 kB (main 701.28 kB, shared chunk 251.64 kB, styles 44.61 kB). The lazy chunk is `roles-section` (`chunk-5MM255DR.js` in that build, 9.13 kB raw, 2.94 kB transferred). The headroom under the cap is 2.46 kB, so Stories 25.5 and 25.6 must put their web code in lazy chunks too.

**Decided in-stage (implement pass 2, 2026-11-13):**
1. `Roles.Refusal` checks, in order: the online demo, the role, an empty or over-long name (`user_unknown`), IRIS's own accounts (`user_system`, by name, before any lookup, so a `%x` name that does not exist is `user_system`), the managed accounts by name (`user_managed`, whether or not the account exists: the service, Workflow and SQL-watch users and the public `demoUser`/`readonlyUser`), the lookup (`user_unknown`) and last the FullName marker (`user_managed`). The task text listed `user_unknown` before `user_managed`; the SQL-watch user must be refused before it exists, so the by-name checks come first.
2. `Assign` runs `Refusal` inside a Try: a job without `%Admin_Secure:USE` cannot enter `%SYS` for the user lookup (a `<PROTECT>`), so `Assign` answers the privilege error that names `%Admin_Secure` instead of throwing (measured by `TestNoPrivilege`).
3. `OnPreDispatch` order: role check (403 `no_role`, from the session's `$Roles`), then the live re-read (401 `signed_out` and `%session.Logout(1)` with `EndSession = 1` when the live roles hold neither role; 500 `server_error` for that one request, with the session kept, when the read fails), then the viewer block, then the admin check. The viewer block refuses when the session's roles say viewer-only OR the live roles do, so a user whose `OcuTalonUser` was removed but who still holds `OcuTalonViewer` is read-only at the next request, not at the next sign-in. The memory GETs of ruling C2 are part of `ViewerMay` (the one place that says what a viewer may do).
4. The test seams that this needs are `Web.Api.LiveRoles` and `Web.Api.RolesInstalled` (private class methods that a probe overrides), `Web.RoleSettings.Offer` (the `SecretHandoff.Put`), `Install.Step.Roles.Audit` (the one audit write, overridden by `Test.Install.ZzRolesAuditFails`) and `SettingsOps.RolesClass`. The probes `ApiProbe`, `HookSettingsProbe`, `MemoryApiProbe`, `FilesProbe` and `DocumentsProbe` answer the live roles as the roles of the test; `ApiProbe.HasUserRole` now admits the viewer by `Shell.HasRole`.
5. The matrix says an empty user and a 161-character user get 400 with reason `user_unknown`, and the task text says `user` is a string of 1 to 160 characters in the route's shape check. The route follows the matrix: `user` must be a string, and `Install.Step.Roles.Refusal` answers `user_unknown` for an empty or over-long one.
6. `POST /v1/session/end` answers 204 (what `Web.Api.EndSession` has always answered), not 200 as the e2e task line says; `api/roles.spec.ts` R3 pins 204.
7. `Test.Core.AnswersInWebRoles.TestDemoApproverOwnSessionOnly` pins `not_found` for another session's request: `AnswersIn.FromPage` answers `not_found` (the route's 404) and only `FromTelegram` calls the same verdict `not_visible`.
8. `Test.Core.SettingsRoles` is not guarded by `Reason`: it runs on `Test.Core.RolesStub`, so it changes no security object and needs no production; the real changes are `RolesAssign`'s, `RolesApi`'s and `LiveRolesApi`'s, which are guarded.
9. The Roles section announces through the `Announcer` (the page's one live region: `announce-focus-sources.test.mjs` forbids any `aria-live` in a template), so "refusals in a polite live region" is the Announcer's, with the refusal text also shown under the form. `announce-focus-sources.test.mjs`, `approval-sources.test.mjs` and `try-it-qa.test.mjs` pin the new speaker, focus call, render wait and the two `@if` forms.
10. `ux-strings.test.mjs`: "Roles" and "Role" are in EXPERIENCE.md, so they sit under `ux`; the other new strings sit under one `ruled` entry for the Planner's rulings.
11. The Settings navigation hides Roles through `shownSections(rolesShown)` (`admin && rolesAssignable && !onlineDemo`); `sectionSlug(part, rolesShown)` sends the address of a hidden Roles to Models.
12. Spine: the additive rows and the AD-13 viewer bullet are in `ARCHITECTURE-SPINE.md` marked `[ADDED 2026-11-13, Story 25.4]`; the lead's replacements are not applied. `lint_spine.py` reports the same 10 low findings as `HEAD`.
13. `docker/tests/test-sign-in.sh` makes the nine fixture roles with `live_fixture_role` (only when absent, no resources) before the users, and the fixture users `ZzViewer` and `ZzRoleTarget`; `web/e2e/support/iris.ts` has the fixture kinds `VIEWER` and `ROLETARGET`. `Test.Web.PublicTexts` classifies `Shell.VIEWERROLE` as not a text (33 such parameters).
14. C3 and C4 are as ruled: DW-1284 and DW-1283 are the lead's; nothing was widened in `SecretHandoff`.

## Planner Gate

**PUBLIC TEXT** (target `web/src/app/settings/roles-view.ts` `ROLES_TEXTS` unless noted; server messages are `Web.RoleSettings` parameters, pinned equal):
1. Nav label and heading: "Roles". From UX: UX-DR141 and EXPERIENCE.md:1143. Target `settings-view.ts`.
2. Intro (RULED 2026-11-13, changed): "Approvers can answer the approval requests that reach them, for every kind of risky action. Viewers can open OcuTalon but can't chat, answer or change anything."
3. Per-kind note: "An approver role for one kind, such as OcuTalonApprover_resend, is granted in IRIS." New.
4. List heading "People with an OcuTalon role"; row text: the user name, then the roles as IRIS names, comma-separated. New.
5. Empty: "No IRIS user holds an OcuTalon role yet." New.
6. Managed row: "Managed by OcuTalon" in place of the buttons. New.
7. Remove buttons: visible "Remove approver" / "Remove viewer"; accessible name "Remove approver from {user}" / "Remove viewer from {user}". New.
8. Grant form: label "IRIS user name"; label "Role"; options "Approver (all risky actions)" and "Viewer (read-only)"; button "Grant". New.
9. Confirmation: "Saved. Applies within a minute. Recorded in the audit log." From UX (EXPERIENCE.md:1100), reused from `settings-view.ts:43`. See question 2.
10. Failure: "Couldn't save. Nothing was changed." Reused from `settings-view.ts:45`. Denied: `settings-view.ts:46`, reused.
11. Load error: "Couldn't load the roles." with the button "Retry" ("Retry" reused from `webhooks-section.ts`). New.
12. Refusals (page and server; (d) added by ruling C1): (d) `user_system` "This is an IRIS system account, so its roles can't be changed here."; (a) `user_unknown` "There is no IRIS user with that name."; (b) `user_managed` "OcuTalon manages this account, so its roles can't be changed here."; (c) `role` "Only the approver and viewer roles can be changed here." New.
13. Online demo, 409 (server `MESSAGEROLESOFF`; visitors can't reach it, because they aren't admins): "Roles can't be changed on the online demo." New.
14. Viewer (server `Web.Api` `MESSAGEREADONLY`, and the line in the composer's place, `shared/viewer-view.ts`): "You have the viewer role, so you can look but not change anything." New.
15. More to try: none. GUIDE.md "New since 1.0.0": none. The section is admin-only, absent on the online demo, and hidden until Story 26.4 creates the roles, so a guide line would not be true yet; it goes with Story 26.4.

**SECURITY:**
1. `GET /api/v1/settings/roles`:
   - Who: an `OcuTalonAdmin` (by whole name; `%All` doesn't count). Everyone else gets 403 `not_admin`; signed out, 401.
   - Returns to the admin only: `{"users":[{user, roles, managed}]}`, IRIS user names and their OcuTalon roles only.
   - On the online demo: 409 `not_available` before anything runs. No body.
2. `POST /api/v1/settings/roles`:
   - Who: as above.
   - The body allow-list is exactly `user` (a string of 1 to 160 characters), `role` (`OcuTalonApprover` | `OcuTalonViewer`) and `grant` (boolean).
   - Returns `{"result":"done","changed"}` or 400 `bad_settings` `{fields, reason}`.
   - On the online demo: 409 `not_available` before the body is read.
3. Every other route: a viewer-only user (`OcuTalonViewer` without `OcuTalonUser`) gets 403 `read_only` on every method but GET, before the body, except `POST /v1/session/end`.
4. The post-sign-in check (`Shell.HasRole`, hence the API, `SessionEvents` and `Live`) admits `OcuTalonViewer` by name.
5. `/v1/state` gains:
   - `viewer`;
   - `rolesAssignable` (a code probe; false on the demo);
   - `admin` reads false for a viewer-only user.
6. A run-time privilege-change path (V3), `Install.Step.Roles.Assign`:
   - It works from an allowlist of exactly `OcuTalonApprover` and `OcuTalonViewer`.
   - It refuses every other role, `%` roles included, and the managed accounts: the service, Workflow and SQL-watch users, the demo and read-only accounts, and any MARKER account.
   - It refuses unknown users, the online demo, and a caller without `%Admin_Secure:USE`.
   - It runs in `SettingsOps`' job (`%All`, `_Ensemble`), reached only from origin `web_admin`.
7. `Holders` reads every user's roles under the same checks.
8. Changes to roles, grants, resources, privileges, tables, columns, indexes or retention: none in product code. The web applications already grant every signed-in user the database roles (`APPLICATIONROLES` begins with `:`), and this story does not change that. `OcuTalonUser` is not widened. The test setup creates fixture roles on throwaways only: `OcuTalonApprover`, the seven `OcuTalonApprover_<kind>` and `OcuTalonViewer`, each with no resources, plus fixture users.
9. User names cross through `SecretHandoff` in both directions:
   - The forward direction is a JSON `{user, role, grant}`.
   - The reverse is the `Holders` list, put by `SettingsOps` and taken once by the REST process.
   - On a submit timeout, a reverse uri may never be taken. It then stays in shared memory until the instance restarts (inference; admin-only, local installs only).
   - User names reach only the IRIS `Settings` audit entry (V4) and the admin's HTTP response.
10. Audit: one `Settings` entry per effective grant or removal: `roles.<user>`, from and to the OcuTalon roles, `irisUser` the acting admin, channel `web`. There is no entry for a refusal or a no-op. A failed entry puts the change back.
11. Tests:
    - Real HTTP (`api/roles.spec.ts`): signed-out 401; LIVE unprivileged `OcuTalonUser` 403 on both routes; README admin success (grant, repeat, remove); every refusal 400; the viewer refused with 403 on every state-changing route and nothing changed.
    - Class-level: the demo 409 for each route (malformed body, no handoff, no submit); the leak scan of the change's message bodies, logs and globals for the target user name; each `Assign` refusal (`Test.Install.RolesAssign`, one method per refusal).

**QUESTIONS:**
1. No half feature before Story 26.4. Options:
   - (a) A `/v1/state` code probe `rolesAssignable`, true only when `Install.Step.Roles` declares `STEP6ROLES = 1`, which Story 26.4 adds in the change that creates the roles. It is the 25.3 `filesReadable` precedent and needs no privilege.
   - (b) A run-time existence check of the two roles through the `ListRoles` command. That is one more command on every Settings load, and the nav entry appears late.
   - (c) Always show the section. That is a half feature.
   - **Recommend (a).**
2. The confirmation text. AC 1 requires the step-2 text, "Saved. Applies within a minute. ...".
   - Grants, and an approver removal, apply at once (`MayAnswer` reads the user's current roles).
   - A signed-in viewer whose viewer role is removed may keep read-only access until their CSP session ends (inference; Task 0 (c) measures it).
   - **Recommend** the step-2 text verbatim. If Task 0 (c) shows the session keeps the role, then for a viewer removal only, use "Saved. Applies when they next sign in. Recorded in the audit log." (new text, for approval now).
3. Whether the README account (`ocutalon`, seed, admin-owned) is assignable. **Recommend yes**: it is not rewritten by the installer. The alternative is to refuse it as installer-managed.
4. The viewer sign-out exception (`POST /v1/session/end`). **Recommend allowed**; otherwise a viewer cannot sign out on the online demo's path or end its durable session.
5. Viewer UI scope:
   - (a) Hide every state-changing control (the UX's "everything read-only"); about 12 component guards.
   - (b) Only the AC's composer, Approve, Reject, Dismiss and Break the feed; the others answer 403 with text 14.
   - **Recommend (a).**
6. One audit entry, written by `Assign`, instead of a second `SettingsOps` entry per change. **Recommend one.**
7. Widening Lane A's contract, additively:
   - `Holders` items gain `managed`;
   - `Assign` gains the trailing arguments `actingUser, sessionRef, channel`;
   - a new `Refusal(userName, role)`, pinned in `Test.Contract.Ac`.
   - **Recommend approve**, with the spine replacements listed in Design Notes.
8. The lead's spine replacements (26.4 → 25.4 for the bodies, the refusal tests and the audit entry) and the epics.md AC 1 amendment (V3). Approve as listed.

## Verification

`$LANE` stands for these variables on every `ci/iris.sh` and `ci/warm.sh` call: `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-a" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=25 stage=implement'`. The fresh tag is `e25s4i` and the warm tag is `e25s4iw`.

Runtime targets:
- The lane's own throwaways (the tags above) for every test run and for Task 0.
- Slot A (profile `ocutalon-slot-a`, namespace `OCUTALON`, passed on every MCP call, `iris_server_info` first) for compile checks and read-only probes only, never a security mutation, with one `iris_execute_tests` per message.

Run one command per tool call, in the foreground, with `timeout: 600000`. Size each call to about 150 s; one test class per call is always safe. Tear down only your own tags, and run `ci/warm.sh down` at the end, also after a failure. Scratch goes under the session scratchpad's `e25s4impl/`.

**Commands:**
- (loop) `$LANE OCUTALON_RUN_TAG=e25s4iw ci/warm.sh up` once. Then one class per call, `$LANE OCUTALON_WARM=1 OCUTALON_RUN_TAG=e25s4iw ci/iris.sh class <Class>`, for each of:
  - `OcuTalon.Test.Install.RolesAssign`, `OcuTalon.Test.Core.SettingsRoles`, `OcuTalon.Test.Web.RolesApi` and `OcuTalon.Test.Web.ViewerApi`;
  - `OcuTalon.Test.Bridge.Api`, `OcuTalon.Test.Contract.Ac`, `OcuTalon.Test.Core.AnswersInWebRoles` and `OcuTalon.Test.Web.Api`;
  - the siblings, which are unchanged and must stay green: `OcuTalon.Test.Web.SettingsApi`, `OcuTalon.Test.Web.HookSettingsApi`, `OcuTalon.Test.Core.SettingsWebhooks`, `OcuTalon.Test.Core.SecretHandoff`, `OcuTalon.Test.Web.Shell`, `OcuTalon.Test.Web.SignIn` and `OcuTalon.Test.Install.Registry`.
  - Expected: each `CLASS … passed`.
- (loop) `node --test web/scripts/roles-view.test.mjs web/scripts/viewer-sources.test.mjs web/scripts/ux-strings.test.mjs web/scripts/api-client-sources.test.mjs web/scripts/floor-sources.test.mjs` -- all pass.
- (loop) e2e, one call each:
  - `$LANE OCUTALON_RUN_TAG=e25s4i ci/iris.sh build`.
  - `npm --silent --prefix web run e2e -- --list --reporter=json > "$SCRATCH/chromium.json"`, then `node web/scripts/e2e-part.mjs k/n "$SCRATCH/chromium.json"`, choosing n so that each part holds at most two spec files.
  - `$LANE OCUTALON_RUN_TAG=e25s4i ci/iris.sh live sign-in --part k/n` for each part that holds `api/roles.spec.ts`, `sign-in/viewer.spec.ts`, `api/api.spec.ts` or `frame/frame.spec.ts`, and `ci/iris.sh live sign-in-2 --part k/n` for the part that holds `settings/roles.spec.ts` or `settings/settings.spec.ts`. Each part passes.
  - `$LANE OCUTALON_RUN_TAG=e25s4i ci/iris.sh teardown`.
- (loop) `uv run --no-cache .claude/skills/bmad-architecture/scripts/lint_spine.py --workspace _bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16` -- `"ok": true`, with no new finding against the baseline.
- (once) `$LANE OCUTALON_RUN_TAG=e25s4i ci/iris.sh live demo-path` -- passes. UJ-1 is unchanged: the demo account is no viewer and no admin.
- (once) `npm --prefix web test`; `npm --prefix web run lint`; `npm --prefix web run build` -- one per call, each passes.
- (once) `bash ci/checks.sh`, in batches of `CHECK_SCRIPTS` if one call cannot hold it -- every block passes, among them `test-class-rules.sh`, `test-boundaries.sh` (ASCII, Rule 14), `test-ci-config.sh` and `test-storage.sh`.
- The full shards and groups are left to CI.

**Shared surfaces:**
- the `/v1/state` key order (`Test/Web/Api.cls:132`, `e2e/api/api.spec.ts:135`, `e2e/frame/frame.spec.ts:607`) and `StateSnapshot`;
- `Web.Api`'s URL map and `OnPreDispatch` order (`SettingsApi`, `ApiProbe`, the Map pins of `DocumentsApi`, `UsageApi`, `HistoryApi` and `FilesApi`);
- `SettingsOps`' `XData Sections` and `Values()` (the `GET /v1/settings` body; `SettingsApi`, `settings.spec.ts`);
- `CommandsIn`'s Routes;
- `Test.Contract.Ac`'s signature count;
- `Test.Bridge.Api`'s stub pins;
- the Settings nav (`SETTINGS_SECTIONS`; `settings.spec.ts:16`, unchanged on the real state);
- the fixture users and roles of `test-sign-in.sh`, which are shared by the three sign-in units;
- the `ux-strings` lists;
- the spine's tables.

Standing criterion: every test added or changed passes on a fresh environment, in either order.

**Mutations to record (Rule 19; one per AC, each observed red and reverted byte-identical):**
- AC 1: drop `OcuTalonViewer` from `ASSIGNABLE` → `RolesAssign` grant and `api/roles.spec.ts` go red. Also remove the `Put` and put the name in `Changes` → the `RolesApi` leak scan goes red.
- AC 2: remove the viewer block in `OnPreDispatch` → `ViewerApi` goes red. Remove the composer guard → `viewer.spec.ts` goes red.
- AC 3: drop `'..ViewerOnly()`, or make `rolesAssignable` ignore `onlineDemo` → the `ViewerApi` demo-role-set case goes red.
- AC 4: move the demo check after the body parse → the `RolesApi` demo test (malformed body) goes red.
- AC 5: make `RolesReady` answer 1 → `RolesApi` and `settings/roles.spec.ts` (real state) go red.
- AC 6: skip the audit write → `RolesAssign` (one entry per change) goes red. Drop the managed-account check → the `RolesAssign` refusal methods go red.

**Recorded (implement pass 2, 2026-11-13).** Tags `e25s4j` (fresh) and `e25s4jw` (warm) stand for `e25s4i`; lock dir lane-a, web port 52801.

- Classes green on the warm stack, one per call: `Test.Install.RolesAssign`, `Test.Core.SettingsRoles`, `Test.Web.RolesApi`, `Test.Web.ViewerApi`, `Test.Web.LiveRolesApi`, `Test.Bridge.Api`, `Test.Contract.Ac`, `Test.Core.AnswersInWebRoles`, `Test.Web.Api`, `Test.Web.SettingsApi`, `Test.Web.HookSettingsApi`, `Test.Core.SettingsWebhooks`, `Test.Core.SecretHandoff`, `Test.Web.Shell`, `Test.Web.SignIn`, `Test.Install.Registry`, and, as the probes and the key order changed, `Test.Web.MemoryApi`, `FilesApi`, `DocumentsApi`, `HistoryApi`, `UsageApi`, `BodyLimit`, `PersonaApi`, `MailboxApi`, `SessionEvents`, `SessionEndApi`, `Live`, `Status`, `PublicTexts`, `Test.Msg.Contracts`, `Test.Core.CommandsStep3` and `CommandsStep4`.
- `node --test` of the whole web suite: 2003 tests pass. `npm --prefix web run lint` and `npm --prefix web run build` pass (the build's initial total is 997.54 kB, under the 1 MB cap; lazy chunk `roles-section`). `bash docker/tests/test-boundaries.sh`, `test-class-rules.sh`, `test-ci-config.sh`, `test-storage.sh` and `test-lib-live.sh` pass. `lint_spine.py`: the same 10 low findings as `HEAD`.
- Live, on fresh throwaways (`ci/iris.sh live sign-in --part 4/30`: `api/pairing`, `api/persona` and `api/roles.spec.ts` 7 pass; `--part 26/30`: `sign-in/viewer.spec.ts` 3 pass; `ci/iris.sh live sign-in-2 --part 17/20`: `settings/email.spec.ts` and `settings/roles.spec.ts` 8 pass, and `--part 11/12`: `settings/settings.spec.ts` 27 of 28 pass before the keyboard step of RS2 was changed to type V; the rerun passed). Not run live: `api/api.spec.ts` and `frame/frame.spec.ts` (their `/v1/state` key order changed, and `Test.Web.Api` pins the same order), the whole `sign-in` and `sign-in-2` units, `live demo-path`, `bash ci/checks.sh`.

**Shared surfaces (record):** `/v1/state` key order (`Test/Web/Api.cls`, `Test/Web/FilesApi.cls`, `e2e/api/api.spec.ts`, `e2e/frame/frame.spec.ts`) and `StateSnapshot`; `Web.Api`'s URL map and `OnPreDispatch` order (`ApiProbe`, `HookSettingsProbe`, `MemoryApiProbe`, `FilesProbe` and `DocumentsProbe` answer the live roles); `SettingsOps`' `XData Sections` and `Values()` (`SettingsApi` green); `CommandsIn`'s Routes (`Test.Msg.Contracts`, `CommandsStep4` green); `Test.Contract.Ac`'s signature count (94; `Assign`'s trailing arguments are pinned too); `Test.Bridge.Api`'s stub pins (`TestRoleCalls`); the Settings nav (`SETTINGS_SECTIONS`, `settings-view.test.mjs`; `settings.spec.ts` S1 green on the real state); the fixture users and roles of `test-sign-in.sh`; the `ux-strings` lists; `announce-focus-sources.test.mjs`, `approval-sources.test.mjs` and `try-it-qa.test.mjs`; `Test.Web.PublicTexts` (`Shell.VIEWERROLE`); the spine's tables.

**Chunk:** the Roles section's web code (`roles-section.ts`, which imports `roles-view.ts`) is the lazy chunk `roles-section` (`chunk-5MM255DR.js`, 9.13 kB); `settings-page.ts` loads it with a dynamic `import('./roles-section')` through a `ViewContainerRef`.

**Mutations (Rule 19), each applied, observed red, reverted byte-identical (`git status --short` and `git diff --stat` unchanged), and the class green again on the same stack:**
- mutation: AC 1, `Parameter ASSIGNABLE` without `OcuTalonViewer` in `Install/Step/Roles.cls` -> `Test.Install.RolesAssign` `TestGrantAndRemove` and `TestAuditFailurePutsTheRoleBack` red.
- mutation: AC 1 / DW-1267, the target's name added to `SaveSettings.Changes` in `Web/RoleSettings.cls` (`{"handoff": uri, "user": name}`) -> `Test.Web.RolesApi` `TestChangesIsOnlyAHandoff` and `TestGrantAndRemove` red.
- mutation: AC 2, the viewer block of `OnPreDispatch` replaced by `If 0 {` -> `Test.Web.ViewerApi` `TestEveryWriteRouteRefusesAViewer` red.
- mutation: AC 2, the composer guard replaced by `@if (false) {` in `chat/chat-panel.ts` (rebuilt bundle) -> `sign-in/viewer.spec.ts` V2 red ("there is no composer").
- mutation: AC 3, `rolesAssignable` without `(body.onlineDemo = 0) &&` -> `Test.Web.ViewerApi` `TestDemoAccount` red; and `admin` without `&& 'readOnly` (`StateBody`) -> `TestStateFlags` and `TestViewerAndAdmin` red.
- mutation: AC 4, the body parsed before the demo refusal in `RoleSettings.Save` -> `Test.Web.RolesApi` `TestOnlineDemo` red (malformed body, 400 instead of 409).
- mutation: AC 5, `RolesReady` answering 1 -> `Test.Web.RolesApi` `TestRolesReady` red. (`settings/roles.spec.ts` RS1 reads the same flag from the real state and was not run against this mutation.)
- mutation: AC 6, the `Assign` audit write replaced by `Set sc = $$$OK` -> `Test.Install.RolesAssign` `TestAuditFailurePutsTheRoleBack` and `TestGrantAndRemove` red; and the managed-account check replaced by `If 0 Quit "user_managed"` -> `TestManagedUserRefused` red.
- mutation: C1, the `user_system` check replaced by `If 0 Quit "user_system"` -> `Test.Install.RolesAssign` `TestSystemUserRefused` red (the grant to `UnknownUser` went through on the throwaway, and the test now takes it back).
- mutation: C-24h, the live re-read's `If '..HasRole(live)` replaced by `If 0 {` -> `Test.Web.LiveRolesApi` `TestRemovedViewerEndsItsSession` and `Test.Web.ViewerApi` `TestLiveRolesRefusal` red.
- mutation: C2, `ViewerMay` answering 1 for a GET of `/v1/memory/items` and `/v1/memory/pinned` -> `Test.Web.ViewerApi` `TestMemoryReadsRefuseAViewer` and `TestEveryWriteRouteRefusesAViewer` red.
- mutation: AC 2 / C-24h (review pass), the two lines that end the session (`Do %session.Logout(1)`, `Set %session.EndSession = 1`) removed from the live re-read's refusal -> `Test.Web.ViewerApi` `TestLiveRolesRefusal` ("the CSP session is ended") and `Test.Web.LiveRolesApi` `TestRemovedViewerEndsItsSession` (401 after the role is given back) red.
- mutation: AC 2 (review pass), `StateBody` reading only the session's roles for `viewer` (the live-roles line removed) -> `Test.Web.ViewerApi` `TestStateFollowsLiveRoles` red.
- mutation: C1 (review pass), `Holders` without `|| (code = "user_system")` in `managed` -> `Test.Install.RolesAssign` `TestHoldersListsSystemAccountAsManaged` red.
- mutation: AC 1 (review pass), `RoleSettings.List` answering 500 instead of 501 for `not_built` -> `Test.Web.RolesApi` `TestListAndSaveOutcomes` red.
- mutation: AC 2 (review pass), `phone/phone-request.ts` without `&& !viewer()` on the simulated phone's buttons -> `web/scripts/viewer-sources.test.mjs` "the simulated phone shows no Approve or Reject for a viewer" red.
- mutation (QA): AC 3's second half, `Core/AnswersIn.cls` falling back to the request's own row when `Ownership.Approval` finds none for the session (the owner rule off) -> `Test.Core.AnswersInWebRoles` `TestDemoApproverOwnSessionOnly` red ("it gets not_found ... for another session's request", "which stays pending"); reverted byte-identical (sha checked), class green again.
- mutation (QA): Matrix "Admin lists, sorted by name without regard to case", `Collect` keying `found` by the raw name instead of its lower case -> the new `Test.Install.RolesAssign` `TestHoldersSortIgnoresCase` red (and `TestHolders` too, on the README account); reverted byte-identical, class green again.
- (QA) tests: `src/ocutalon/cls/OcuTalon/Test/Install/RolesAssign.cls` extended with `TestHoldersSortIgnoresCase` (two fixture users whose raw and lower-case orders differ; the old sort check passed only when the README account held a role). No new class, so `ci/units.sh` is unchanged (`new_units: none`). The warm run was tag `e25s4qw`: `Test.Install.RolesAssign` and `Test.Core.AnswersInWebRoles` passed.
- mutation (code review): AC 2 / ruling C2, `|| readOnly` dropped from the settings admin check in `Web.Api.OnPreDispatch` -> `Test.Web.ViewerApi` `TestViewerAndAdmin` red (the three settings GETs of a viewer who holds OcuTalonAdmin passed); restored from a saved copy, byte-identical (`git status --short` and `git diff --stat` unchanged), class green again.
- mutation (code review): AC 1, `SaveRoles` answering a Refusal of `online_demo` as a refusal (its `not_available` line made `If 0`) -> `Test.Core.SettingsRoles` `TestRefusalCodes` red ("online_demo gives not_available"); restored byte-identical, class green again. (Removing `SaveRoles`' inner Try stayed green: `OnMessage` already answers a throw as `failed`.)
- mutation (rework, DW-1290): `Web.Api.IsAdmin` reading `Held(..Roles())` (the session's roles) instead of the live set -> `Test.Web.ViewerApi` `TestAdminFollowsLiveRoles`, `Test.Web.RolesApi` `TestRemovedAdminIsRefused` (the route's own `Refusal` too) and `Test.Web.LiveRolesApi` `TestRemovedAdminLosesSettings` (real HTTP: the next `GET /v1/settings` stayed 200) red; restored from a saved copy (sha checked), classes green again on the same warm stack.
- mutation (rework review, DW-1290 condition 2): `Web.Api.IsAdmin` answering 1 (not 0) when the live read fails -> `Test.Web.ViewerApi` `TestAdminFollowsLiveRoles` red ("no admin is shown while the live read fails"); restored from a saved copy, byte-identical (`git status --short` and `git diff --stat` unchanged), class green again.
- mutation (rework review, DW-1290 no cache): `Web.Api.IsAdmin` keeping its first answer in the CSP session (`%session.Data`) -> `Test.Web.LiveRolesApi` `TestRemovedAdminLosesSettings` red (the next `GET /v1/settings` stayed 200); restored byte-identical, class green again.
- mutation (rework, DW-1297): `Install.Step.Roles.Assign` with its `If before = after Quit` made `If 0 Quit` (a no-op writes an entry and answers changed true) -> `Test.Web.RolesApi` `TestNoChangeWritesNoEntry` and `TestGrantAndRemove`, and `Test.Install.RolesAssign` `TestGrantAndRemove`, red; restored byte-identical (sha checked), classes green again on the same warm stack.
- mutation (rework, DW-1297): `roles-view.ts` `saveLine` made to ignore `changed: false` (`if (false && answer?.changed === false)`, so the saved text shows for a no-op) -> `web/scripts/roles-view.test.mjs` `saveLine` (2 tests) red, and, with the bundle rebuilt, `web/e2e/settings/roles.spec.ts` RS3 red on a fresh throwaway ("a grant of a role the user already holds shows the no-change text"); restored byte-identical (sha checked), the bundle rebuilt and `live sign-in-2 --part 17/20` green again.
- (rework) tests added: `Test.Web.ViewerApi` `TestAdminFollowsLiveRoles`, `Test.Web.RolesApi` `TestRemovedAdminIsRefused` and `TestNoChangeWritesNoEntry`, `Test.Web.LiveRolesApi` `TestRemovedAdminLosesSettings`, `web/scripts/roles-view.test.mjs` (`saveLine`, the section's saved line), `web/e2e/settings/roles.spec.ts` RS3; the no-op rows of `Test.Install.RolesAssign` `TestGrantAndRemove` already pinned "no entry" at the class level. The new text sits under `ruled` in `ux-strings.test.mjs` and only in the lazy chunk `roles-section` (9.42 kB); the initial bundle is 997.59 kB (cap 997.59). Warm tag `e25s4kw` and fresh tag `e25s4k`, both torn down.
- (code review) tests changed, warm tag `e25s4cw` and fresh tag `e25s4c` on lane A, both torn down: `Test.Web.ViewerApi`, `Test.Web.RolesApi`, `Test.Core.SettingsRoles`, `Test.Install.RolesAssign`, `Test.Core.AnswersInWebRoles`, `Test.Web.SettingsApi`, `Test.Web.HookSettingsApi` and `Test.Web.LiveRolesApi` passed; `ci/iris.sh live sign-in --part 26/30` (`sign-in/viewer.spec.ts`, 3) and `live sign-in-2 --part 17/20` (`settings/email.spec.ts`, `settings/roles.spec.ts`, 8) passed; `npm --prefix web test` 2005 pass, `run lint` passes, `run build` initial total 997.59 kB (lazy chunk `roles-section` 9.19 kB); `test-boundaries.sh` and `test-class-rules.sh` pass. Not mutated: V2's new controls and RS2's focus check (each needs a rebuilt bundle and a fresh stack per run).
- (QA) not mutated: AC 6's keyboard and label half (`settings/roles.spec.ts` RS2, which reads every control by `getByLabel`/`getByRole` name); it needs a fresh stack and a rebuilt bundle, and AC 6 already has two demonstrated mutations.

## Auto Run Result

Status: done
Blocking condition: none

Summary. Story 25.4 builds `Install.Step.Roles.Assign`, `Refusal` and `Holders` (allowlist of `OcuTalonApprover` and `OcuTalonViewer`, the refusals including `user_system`, one `Settings` audit entry per effective change, put-back when the entry fails), the `ListRoles` read verb and `SettingsOps.SaveRoles`, the admin-only `Web.RoleSettings` routes with `SecretHandoff` in both directions, the viewer role (`Shell.HasRole`, `ViewerOnly`, 403 `read_only` in `OnPreDispatch`, the two memory GETs refused, `/v1/state` `viewer` and `rolesAssignable`), the live role re-read (ruling C-24h; p95 0.066 ms over 250 calls, no cache), the viewer guards in 14 components, the lazy `roles-section` chunk (initial bundle 997.59 kB of 1 MB) and the Settings > Roles section. `new_units: none`; `ci_groups` as in Design Notes decision 12.

Files. Lane A: `Install/Step/Roles.cls`. Core: `Core/SettingsOps.cls`, `Core/CommandsIn.cls`, `Msg/Command/ListRoles.cls`. Web: `Web/Api.cls`, `Web/RoleSettings.cls`, `Web/Public/Shell.cls`. Tests: `Test/Install/RolesAssign.cls`, `Test/Core/SettingsRoles.cls` (with `RolesStub`, `SettingsRolesProbe`), `Test/Web/RolesApi.cls`, `ViewerApi.cls`, `LiveRolesApi.cls`, probes, `Test/Bridge/Api.cls`, `Test/Contract/Ac.cls`, `Test/Core/AnswersInWebRoles.cls`. Web: `viewer-view.ts`, `roles-view.ts`, `roles-section.ts`, `settings-page.ts`, `settings-view.ts`, `api-client.ts`, `api-types.ts` and the viewer guards; unit and e2e specs; `docker/tests/lib-live.sh` and `test-sign-in.sh` fixtures; spine rows.

Review. 37 findings in 30 rows, patches applied in 11 rows (6 medium, 5 low), deferred 2 (see frontmatter), the rest rejected with their reasons in the Review Triage Log. Follow-up review recommended: true, because six medium findings were patched in this pass; the unverified risk is the new live-roles reading in `StateBody` and `OnPreDispatch` (viewer flag from the session's or the live roles) and the tests added for it.

Verification (this pass, after the last patch). Warm stack (tag e25s4jw), one class per call, all passed: `Test.Install.RolesAssign`, `Test.Core.SettingsRoles`, `Test.Web.RolesApi`, `Test.Web.ViewerApi`, `Test.Web.LiveRolesApi`, `Test.Bridge.Api`, `Test.Contract.Ac`, `Test.Core.AnswersInWebRoles`, `Test.Web.Api`, `Test.Web.SettingsApi`, `Test.Web.HookSettingsApi`, `Test.Core.SettingsWebhooks`, `Test.Core.SecretHandoff`, `Test.Web.Shell`, `Test.Web.SignIn`, `Test.Install.Registry`, `Test.Web.DocumentsApi`, `FilesApi`, `UsageApi`, `HistoryApi`, `MemoryApi`, `SessionEvents`, `PublicTexts` and `Test.Msg.Contracts`. `node --test` of the five listed web scripts: 110 pass; `npm --prefix web test` 2005 pass; `npm --prefix web run lint` and `run build` pass. Live on fresh throwaways (tag e25s4j): `sign-in` parts 1/30 (api.spec, 20), 4/30 (roles.spec, 7), 19/30 (frame.spec, 21) and 26/30 (viewer.spec, 3), `sign-in-2` part 17/20 (roles.spec, 8) and `live demo-path` all passed. `bash ci/checks.sh`: all 32 scripts passed. `lint_spine.py`: the same 10 low findings as `HEAD`. Five new mutations observed red and reverted (Verification). Both tags torn down.

Residual risks. The initial bundle has 2.4 kB of headroom under the 1 MB cap, so Stories 25.5 and 25.6 must lazy-load their web code. The Roles section is hidden on a real install until Story 26.4 adds `STEP6ROLES`, so its page flow is exercised with a stubbed state flag (`settings/roles.spec.ts` RS2); the routes underneath are real. C3 (DW-1284) and C4 (DW-1283) are the lead's.

### Rework pass 1 (DW-1290, DW-1297; this pass only)

Summary. `Web.Api.IsAdmin` reads the live role set (no cache; a failed read answers 0 for that call and keeps the session), so `/v1/settings` and below, `/v1/state` `admin` and `RoleSettings.Refusal` follow a removed `OcuTalonAdmin` at the next request. The Roles section shows "No change: {user}'s roles are already as you set them." for a save that changed nothing (`roles-view.ts` `saveLine`, lazy chunk only); the server already wrote no entry for it. Ruling 1 needed nothing (self-lockout is DW-1303 on 25.5). The second `deferred:` item (the admin role applying until the session ends) is removed, because this pass fixes it.

Files. `Web/Api.cls`, `Web/RoleSettings.cls` (contracts), `web/src/app/settings/roles-view.ts`, `roles-section.ts`; tests `Test/Web/ViewerApi.cls`, `RolesApi.cls`, `LiveRolesApi.cls`, `web/scripts/roles-view.test.mjs`, `ux-strings.test.mjs`, `web/e2e/settings/roles.spec.ts` (RS3).

Review. 24 findings from four layers, 0 high, 0 medium; 2 low patched (a stale header line; two mutation lines observed), the rest rejected with their reasons in the Review Triage Log. Follow-up review recommended: false (no high patched).

Verification (this pass). Warm stacks `e25s4kvw`, `e25s4kmw` (this stage), `e25s4kw` and fresh `e25s4k` (implement pass), all torn down; `ViewerApi`, `RolesApi`, `LiveRolesApi`, `Test.Web.Api`, `SettingsApi`, `HookSettingsApi` and `Test.Install.RolesAssign` passed; the five web node scripts (115), `npm --prefix web test` (2010), `run lint` and `run build` pass; live `sign-in-2` part 17/20 (RS3) passed in the implement pass; `test-boundaries.sh` and `test-class-rules.sh` pass. Initial bundle 997.59 kB (cap 997.59); `roles-section` chunk 9.42 kB. Five mutations observed red and reverted byte-identical (Verification).

Residual risks. The initial bundle sits exactly at the cap. `SessionEvents` reads the session's roles for the sign-in admin flag (out of scope, not changed).
