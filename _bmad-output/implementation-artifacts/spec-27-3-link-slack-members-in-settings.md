---
title: 'Story 27.3: Link Slack members in Settings'
type: 'feature'
created: '2026-11-16'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-27-context.md'
warnings: [oversized]
deferred: []
---

<intent-contract>

## Intent

**Problem:** Story 27.1 shipped the Slack route, `SlackIn` and the `Data.SlackLink` table, but nothing writes a link: `Link`/`Unlink` have no product caller, so no Slack direct message can become a turn on a real install. An admin also cannot see in Settings whether Slack is on, and the approved Slack texts (R12) are not shipped.

**Approach:** Add three admin-only command verbs to `SettingsOps` (list, link, unlink) behind a new admin REST class under `/api/v1/settings/channels/slack`, following the webhook and on-call patterns: names and member ids travel only through `SecretHandoff`, each change writes one `Settings` audit entry first. A link goes to the user's one durable session (`Data.Session.ForUser`), with the workspace `team_id` that `SlackIn` notes from signed events, so nothing calls slack.com. Settings › Channels gets a lazily loaded Slack group (state from `SlackIn.On()`, the address, the linked-members list with link and unlink). The web chat marks turns of channel `slack` "via Slack". The approved texts ship verbatim in `Msg.Catalog.Core`, `EXPERIENCE.md` and a `GUIDE.md` Slack section. The spine records how an admin links a member and carries DW-1442's AD wording fixes once the Planner rules them.

## Boundaries & Constraints

**Always:**
- Admin only: every route refuses a user without `OcuTalonAdmin` (and a viewer) with 403 `not_admin` (Api's `OnPreDispatch` plus the class's own `Refusal()`), and the three verbs are accepted from origin `web_admin` only (AD-1). The user role is never widened.
- The web process reads no stored row (CI rule `web-global-reads`): the list, the roster and Slack's state come from `SettingsOps` in the production job, and the list comes back only as a `SecretHandoff` uri that the route takes once (AD-13, AD-24).
- Member ids, team ids and user names other than the acting admin's are in no traced message, `CommandResult`, log line, trace or global outside `Data.SlackLink`'s storage (R8, AD-24). The `Settings` audit entry may name the linked IRIS user (AD-17 V4 bullet) and never holds a member id or team id.
- Audit first: a link or an unlink writes its `Settings` audit entry before the row changes; a failed audit write changes nothing (`not_audited`). A refused request writes no audit entry and changes nothing.
- Slack's state on the page is the answer of `OcuTalon.Channel.Slack.In.On()`, read in the production job at list time; Settings never re-derives it.
- Online demo: every Slack settings route answers 409 `not_available` with `settings.slackOffOnDemo` before anything is read, handed over or submitted; each verb refuses `not_available` on its own too (a link's handoff is discarded first). The page shows only `settings.slackOffOnDemo`.
- The approved R12 texts ship word for word (catalog keys, `EXPERIENCE.md`, the setup steps). Setup step 1 has no `chat:write` (Story 27.2 adds it).
- New web code for the Slack group is a lazy chunk; the initial bundle stays under its cap (`web/scripts/initial-bundle.test.mjs`, 921,000 bytes; `angular.json` 1 MB), which is never raised.

**Never:**
- No call to slack.com or any outside service; no new environment variable, `Data.Setting` key, role, resource or grant (R10).
- No public text beyond the approved strings until the Planner rules the gate list (a): the two new refusal texts and the GUIDE heading ship only as ruled.
- No AD wording change before the Planner's ruling on gate item (f).
- No edit to `Data/Purge.cls`, `settings-view.ts`, `on-call-section.ts`, `Production.cls`, any Telegram class or any Lane A file; no new production item or table.
- No change to model-facing text (R7 stands), to the turn text Slack sends (the `&amp;` and mention-markup residual stays with Story 27.2), or to `Msg/Catalog.cls` `CHANNELS` (Story 27.2's).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| List, Slack on | README admin, `GET /api/v1/settings/channels/slack`, both `SLACK_*` set, not demo | 200 `{"state":"on","path":"/ocutalon/hook/slack/events","links":[{ref,user,member}],"users":[name...]}`; page shows `slackOn`, `slackAddress` with this origin, the list (or `slackNoMembers`) and the form | Take failure or other outcome → 500 `server_error` |
| List, Slack off | either variable empty | 200 with `"state":"off"`; page shows `slackNotSetUp` and the `slackHowTo` link (GUIDE.md#slack, new tab), then the members part | as above |
| Online demo | any Slack route, flag on | 409 `not_available`, message `settings.slackOffOnDemo`; nothing submitted; page shows only that line | — |
| Not an admin | LIVE OcuTalonUser, or a viewer, on any Slack route | 403 `not_admin`; nothing submitted | — |
| Bad body | POST body not exactly `{"user":string,"member":string}` | 400 `bad_settings` `{fields}` with `MESSAGEBADSETTINGS`; nothing handed over | — |
| Link | POST `{user, member}`; user has a session row; a workspace is noted; member and user free | 200 `{"result":"done","link":{ref,user,member}}`, message `slackLinked`; one audit entry `slackLink.<ref>` (from "" to user); the user's next DM to the bot becomes a turn | Audit write fails → 500, no row |
| Bad member id | member not `U`/`W` + 2-31 letters or digits after trim and upper-casing | 400 `bad_slack_link` `{fields:["member"],reason:"bad_member"}`, message `slackBadMemberId`; the page checks it before sending | — |
| Member taken | member already linked to another user | 400, `{fields:["member"],reason:"member_taken"}`, `slackMemberTaken` | — |
| User taken | the user's session already has another member | 400, `{fields:["user"],reason:"user_taken"}`, `slackUserTaken` with `{user}` | — |
| Same pair again | member already linked to that user | 200 done (the existing link), audited as a link | — |
| Unknown user | user with no session row (never signed in) | 400, `{fields:["user"],reason:"user_unknown"}`, gated text `settings.slackUnknownUser` | — |
| No workspace yet | no signed event has been noted | 400, `{fields:[],reason:"no_workspace"}`, gated text `settings.slackNoWorkspace` | — |
| Unlink | `DELETE /api/v1/settings/channels/slack/<ref>` | 200 done, message `slackUnlinked`; audit (from user to ""); the member's next DM is `Ignored` (`unlinked`) | Unknown ref → 404 `not_found` (`MESSAGENOTFOUND`), no audit |
| Workspace noted | signed event with a valid `team_id` reaches `SlackIn` | `^OcuTalonP.SlackW` holds that team id (overwritten when it differs); nothing else | Slack off → `SlackIn` refuses, nothing noted |
| Chat marker | a Turn of channel `slack` in the web chat | its caption reads "via Slack" | — |

</intent-contract>

## Code Map

All classes under `src/ocutalon/cls/OcuTalon/`. Lane B (AD-29) unless marked.

**Data and channel (own files):**
- `Data/SlackLink.cls` -- `Link` :67-98 (one combined "already linked" error at :91 on a failed `%Save`; no reason output), `Unlink(sessionRef)` :101-115 (by session), `IsId` :118, `SessionFor` :50-63, `LinkedInAnotherTeam` :162-182, `EVENTGLOBAL` :18 (precedent for a non-table global parameter), indexes `RefIndex` :41, `MemberIndex(TeamId,MemberId)` :43, `SessionRefIndex` :45, cascading `SessionFK` :47. No list method exists.
- `Channel/Slack/In.cls` -- `On(demo="")` :51-57 (env + `Data.Setting.Get("onlineDemo")`); `OnProcessInput` :60-80: claim at :68, then `Classify`. The workspace note goes right after a successful claim.
- `Data/Session.cls` -- `IrisUser` :34, `IrisUserIndex` :76 (not unique), `ForUser(irisUser,.sc)` :84-118 (lock, oldest row by ID, creates one if none; its error text names the user, so never pass it to a result).
- `Data/Purge.cls` (Lane D, READ ONLY) -- `Keeps` :121-136 has no SlackLink line; R8 relies on that (Decided 4).

**Settings operation and commands:**
- `Core/SettingsOps.cls` (CONTENDED, Lane A 25.9) -- `Carry` :207-228 (class-name chain, unknown at :227); `CHANNELS` :181; `AuditData` :261-272; `WriteAudit` :282-285 (only audit writer, test seam); `HasSession` :720; `OnlineDemo` :731; `Result` :837; `CreateWebhook` :2301-2342 (audit-first order, reversing entry on a failed save); `WebhookFieldText(key,value)` :2463 (catalog render, public); `ListRoles` :2477-2493 and `ListOnCallUsers` :2739-2756 (handoff-list pattern); `OnCallUsers(.users,.paired)` :2714-2734 (the roster: users with a Session row; reuse it).
- `Core/CommandsIn.cls` -- Routes rows :344-388 (`CreateWebhook` :379-380, `ListRoles` :386, `ListOnCallUsers` :387); refusal of other origins with `MESSAGEADMINONLY` :120.
- `Core/SecretHandoff.cls` -- `Put` :26, `Take` :52, `Discard` :77.
- `Msg/Command/CreateWebhook.cls` (Handoff, ActingUser) and `Msg/Command/ListRoles.cls` (no properties) -- shapes for the three new verbs.

**Web (server):**
- `Web/Api.cls` (CONTENDED, Lane D) -- UrlMap Map lines :311-319 (`/v1/settings/mcp` :319 is the last); `OnPreDispatch` :338-382 (403 for settings URLs :362); `IsAdmin` :392; `HandOff` :1222-1236; `Submit` :1241-1244 (test seam); `Fail` :1623; messages `MESSAGENOTFOUND` :192, `MESSAGESERVERERROR` :198, `MESSAGENOTADMIN` :206, `MESSAGEBADSETTINGS` :209.
- `Web/RoleSettings.cls` -- the class to extend in shape: extends `Web.Api`, `Refusal()` (admin + viewer + demo), `List` takes the handoff once, `Save` validates the exact body before handing over. `Web/HookSettings.cls` -- `Answer` :132-161 outcome→HTTP map.
- `docker/tests/test-class-rules.sh` -- `web-global-reads` (:37-49, :648+): no `^OcuTalonP.` and no generated `%OpenId`/`<Index>Open`/`Exists` on product classes in `OcuTalon.Web*`.

**Catalog and docs:**
- `Msg/Catalog/Core.cls` -- `XData Entries` :14; `settings.webhook*` :757-815 (entry shape `{"text","slots","source":"EXPERIENCE Message Catalog / <section> / <case>"}`). No `chat.*` key exists yet.
- `Test/Msg/Catalog.cls` -- `TestEntries` :74 (asserts 161 Core keys and the `XData Keys` list from :1117, settings rows about :1259-1268); `TestEveryKeyOnEveryChannel` :139 (needs an `XData Fixtures` entry, :1664+).
- `_bmad-output/planning-artifacts/ux-designs/ux-OcuTalon-2026-10-16/EXPERIENCE.md` -- Message Catalog :757-1104 (`| Case | Text |`, row example :1001, tagged row :1004), "Settings (step 5)" from :1057; Later Steps :1122-1239 (Step 6 :1165, Personality :1176; no Step 7); Settings › Channels line :1157. Planning artifact: editing it makes `epic-27-context.md` stale (the lead re-warms).
- `GUIDE.md` -- `## Telegram` :231, `## Gmail and Microsoft 365` :243; no Slack section.

**Web (client):**
- `web/src/app/settings/channels-section.ts` -- template :25-53 (`<app-webhooks-section />` :52 is last); not contended.
- `web/src/app/settings/webhooks-section.ts` + `webhooks-view.ts` -- state machine (`loading|ready|off|denied|failed`), `webhookOutcome(status, body)` :33-49, `addressText` (origin + path), refusal handling :376-412. Shape for `slack-section.ts` / `slack-view.ts`.
- `web/src/app/settings/roles-view.ts` (`ROLES_TEXTS`) -- precedent for a section's own texts module, so `settings-view.ts` (contended) is not edited.
- `web/src/app/settings/settings-page.ts` :108-109, :250, :324-333 -- lazy section by `import()` + `ViewContainerRef.createComponent` (roles); copy into `channels-section.ts`.
- `web/src/app/links.ts` `GUIDE_URL` :11; `rail/rail-view.ts` `readmeSection(url, anchor)` :202; channels' Telegram "How to set it up" link :33-36.
- `web/src/app/api/api-client.ts` :87-105 (webhook calls, `BASE` :48) and `api-types.ts` -- add the Slack calls and types.
- `web/src/app/chat/chat-view.ts` (CONTENDED, Lane D) -- `CHAT_TEXTS` :48, `viaTelegram` :63, `captionOf` :349-355; channel arrives as `channel` (`live/payloads.ts:144`).
- `web/scripts/webhooks-view.test.mjs` :14-31 (texts == catalog parity, the model for `slack-view.test.mjs`); `chat-view.test.mjs` (CONTENDED) captions :168-176, `CHAT_TEXTS` deep-equal :538-560; `ux-strings.test.mjs` (CONTENDED) `IMPORTED` :41-81, `SOURCES` :183 (`ux` = verbatim in EXPERIENCE.md); `initial-bundle.test.mjs` :21; `lazy-routes.test.mjs` :84-104.
- E2E: `web/e2e/api/webhooks.spec.ts` (README admin `admin(request)` :54, LIVE user context :162/:185; project chromium = `live:sign-in`); `web/e2e/settings/webhooks.spec.ts` :30-47 (region, `page.route` 409/403/500, `irisScript` cleanup; project sign-in-2 = `live:sign-in-2`); `web/e2e/chat/chat.spec.ts` :560-575 (`seedTurns` with a telegram turn and its "via Telegram" caption). `web/e2e/sign-in/helpers.ts:16` README account, `:76` `signInOverHttp`; `web/e2e/support/iris.ts:74` `fixtureUser('LIVE')`.

**Tests to extend or copy:**
- `Test/Data/SlackLink.cls`, `Test/Channel/SlackIn.cls` + `SlackInProbe.cls` (own, Story 27.1).
- `Test/Core/SettingsWebhooks.cls` (CONTENDED, read only) -- shadow `Test.Core.SettingsOpsProbe` (CONTENDED, used, not edited) with a real SecretHandoff, helpers `Create`/`Handoff`/`Carry` :138-167; the model for the new `Test/Core/SettingsSlack.cls`.
- `Test/Web/HookSettingsApi.cls` + `HookSettingsProbe.cls`, `Test/Web/RolesApi.cls` + `RoleSettingsProbe.cls` -- route-probe pattern (`^OcuTalonTest("ApiProbe","roles")`, `Submit` override).
- `Test/Msg/Contracts.cls` verbs list :42 and entries (ListRoles, CreateWebhook); `Test/Core/CommandsRouting.cls` (`TestProposeFixToolOnly` :442 shape).
- `docker/tests/test-slack-hook.sh` (own) -- phase 2 seeds the link with `Link(...)` at :150 via `iris_script`; curl sign-in precedents: `docker/tests/test-documents.sh`, `lib-online.sh` (`IRISUsername`).

## Tasks & Acceptance

**Execution (in this order):**
- **Task 0 (implement stage, first; lane-B throwaway, never slot B):** on a stack with the Slack override (the `live:slack-hook` recipe), prove that `SlackIn`, in the hook process under the `OcuTalonWebhook` role's existing grants, can `Set` and read `^OcuTalonP.SlackW`. Record the result under `## Verification` › "Task 0 record". If any new grant, role or resource would be needed: STOP, write nothing else, HALT `blocked` with `intent gap: R10 new grant needed` naming the privilege.
- `Data/SlackLink.cls` -- (1) `Link(teamId, memberId, sessionRef, Output sc, Output reason, ref As %String = "")`: trailing `reason` output (`""`, `bad_id`, `no_session`, `member_taken`, `user_taken`, `failed`) and an optional `ref` the caller made with `Bridge.Ids.NewRef()` (else one is made, as today); the member already linked to that same session returns the existing Ref with OK; a failed save re-checks the two unique indexes to name the clash. Existing callers (tests, `test-slack-hook.sh`) keep working unchanged. (2) `Taken(teamId, memberId, sessionRef) As %String` -- `""`, `same`, `member_taken` or `user_taken` (index `Exists` reads), for the operation's check before its audit entry. (3) `List() As %DynamicArray` -- `[{ref, sessionRef, member}]` in ID order, object access (precedent `PartnerContact.List`). (4) `WORKSPACEGLOBAL` `^OcuTalonP.SlackW`, `NoteWorkspace(teamId)` (sets only an `IsId` value, and only when it differs) and `Workspace() As %String`. Status texts hold no id. Class doc updated.
- `Channel/Slack/In.cls` -- after a successful `ClaimEvent` (:68), `Do ##class(OcuTalon.Data.SlackLink).NoteWorkspace(event.TeamId)`. No other change. Class doc: one line.
- `Msg/Command/ListSlackLinks.cls`, `LinkSlackMember.cls` (`Handoff` %String(MAXLEN 200), `ActingUser` MAXLEN 160), `UnlinkSlackMember.cls` (`LinkRef` MAXLEN 22, `ActingUser`) (new) -- shapes of `ListRoles` / `CreateWebhook`.
- `Core/CommandsIn.cls` -- three Routes rows `{"verb":"ListSlackLinks"|"LinkSlackMember"|"UnlinkSlackMember","owner":"SettingsOps","origins":"web_admin"}` after `ListMcpServers`/`ListProductions`. Not tool verbs.
- `Core/SettingsOps.cls` (CONTENDED, gate e) -- three `If class = ... Quit ..<Method>(command)` lines in `Carry` before :227, and one appended block at the end of the class:
  - `ListSlack(command)`: not `web_admin` → `not_allowed`; demo → `not_available` (`settings.slackOffOnDemo`); builds `{state: On()?"on":"off", path:"/ocutalon/hook/slack/events", links:[{ref, user (the session's IrisUser), member}], users:[names from OnCallUsers]}`, `SecretHandoff.Put`, answers `listed` with `{"handoff":uri}`.
  - `LinkSlack(command)`: `TakeSecret` first; demo → `not_available`; handoff error → `failed`; `HasSession(command.SessionRef)` false → `no_session`; parse `{user, member}`; member trimmed and upper-cased, must match `U`/`W` + 2-31 letters/digits else `refused` `{reason:"bad_member",field:"member"}`; user not in `OnCallUsers` → `user_unknown`; `Workspace()` empty → `no_workspace`; session = `Session.ForUser(user)`; `Taken` → `member_taken`/`user_taken`; the Ref is made first (`Bridge.Ids.NewRef()`, or for `same` the existing link's Ref from `MemberIndexOpen`); audit first (`AuditData(command.Origin, command.ActingUser, command.SessionRef, "slackLink."_ref, "", user)`), failure → `not_audited`; then `Link(team, member, session, .sc, .reason, ref)`; a failed link writes the reversing entry (`from` user, `to` "") and answers `refused` with its reason (`failed` → `failed`). Done → `Result(1,"done","", {"ref":ref})` (no names in the result).
  - `UnlinkSlack(command)`: demo → `not_available`; `RefIndexOpen(LinkRef)` none → `not_found`; audit (`from` the session's IrisUser, `to` ""), failure → `not_audited`; `Unlink(row.SessionRef)` → `done`.
  - Messages in results are reasons only; the route renders texts.
- `Web/SlackSettings.cls` (new, extends `Web.Api`, shape of `RoleSettings`) -- UrlMap `GET ""` → `List`, `POST ""` → `Save`, `DELETE "/:ref"` → `Remove`; private `OnlineDemo()` and `Refusal()` (403 `not_admin` for a non-admin or viewer; 409 `not_available` with `settings.slackOffOnDemo` via `SettingsOps.WebhookFieldText`); `Save` validates the exact body (else 400 `bad_settings` `{fields}`), hands it over with `HandOff` (discarded on every path) and maps: `done` → 200 `{"result":"done","message":slackLinked,"link":{ref,user,member}}`; `refused` → 400 `bad_slack_link` `{fields,reason}` with the reason's text (`{user}` filled in this process); `not_available` 409; anything else 500 `server_error`. `Remove`: `done` → 200 `{"result":"done","message":slackUnlinked}`, `not_found` → 404 `MESSAGENOTFOUND`. `List` takes the handoff once and answers 200 with it. Reads no row (`web-global-reads`).
- `Web/Api.cls` (CONTENDED, gate e) -- one line `<Map Prefix="/v1/settings/channels/slack" Forward="OcuTalon.Web.SlackSettings"/>` after the `/v1/settings/mcp` Map line.
- `Msg/Catalog/Core.cls` -- the 18 approved `settings.slack*` keys and `chat.viaSlack` verbatim (gate a), plus the two gated keys as ruled; `source` `EXPERIENCE Message Catalog / Slack (step 7) / <case>`; slots `slackAddress {address: text}`, `slackUserTaken {user: text}`.
- `Test/Msg/Catalog.cls` -- count 161 → 182 (19 approved keys plus the two gated ones; if the Planner drops or rewords a gated text, the lead records it in the Spec Change Log and the count follows), the `XData Keys` list and one `XData Fixtures` entry per new key.
- `EXPERIENCE.md` -- a "Slack (step 7)" block at the end of the Message Catalog (one row per key, `[ADDED <date>, Story 27.3, approved R12]`), and in Later Steps `### Step 7: Slack` with the four approved setup steps verbatim, one bullet for Settings › Channels › Slack and one for "via Slack".
- `GUIDE.md` -- `## Slack` (anchor `slack`) after `## Gmail and Microsoft 365`: the four approved setup steps verbatim as a numbered list, nothing else (heading gated, a).
- `web/src/app/settings/slack-view.ts` (new, framework-free) -- `SLACK_TEXTS` (the 18 approved strings + the two gated ones), `memberIdProblem(text)`, `slackOutcome(status, body)` (403 → denied, 409 `not_available` → off, 400 `bad_slack_link` → field/form, else failed), `slackState(list)`.
- `web/src/app/settings/slack-section.ts` (new, lazy) -- region named `slackHeading`; states per the matrix (demo line only; off → `slackNotSetUp` + `slackHowTo` link to `readmeSection(GUIDE_URL, 'slack')` with the existing opens-in-new-tab text; on → `slackOn` + `slackAddress` with `window.location.origin + path`); members part: `slackMembersHeading`, `slackMembersHelp`, rows (user, member id, `slackUnlink` button described by its row) or `slackNoMembers`, form (`slackMemberId` input, `slackMemberUser` select of `users`, `slackLink` button); success announces `slackLinked`/`slackUnlinked` and reloads; refusals show under their field; load failure and retry reuse the webhooks section's existing texts.
- `web/src/app/settings/channels-section.ts` -- a `#slackHost` after `<app-webhooks-section />`, filled once with `import('./slack-section')` + `createComponent` (roles pattern); no static import of the section; class doc line.
- `web/src/app/api/api-client.ts`, `api-types.ts` -- `slack()`, `linkSlack({user, member})`, `unlinkSlack(ref)` and their types.
- `web/src/app/chat/chat-view.ts` (CONTENDED, gate e) -- `viaSlack: 'via Slack',` after :63; `if (channel === 'slack') return CHAT_TEXTS.viaSlack;` beside the telegram line in `captionOf`.
- `ARCHITECTURE-SPINE.md` -- after the Planner's ruling only, apply gate item (f) exactly (DW-1442 and the linking edits), each tagged as ruled; `memlog.py append`; `lint_spine.py` `"ok": true` (no placeholder finding beyond the 13 pre-existing lows); refresh `updated:`.
- **Tests:**
  - `Test/Data/SlackLink.cls` -- `TestLinkReasons` (each reason, same pair), `TestTaken`, `TestList`, `TestWorkspace` (valid noted, invalid ignored, overwrite only on change).
  - `Test/Channel/SlackIn.cls` -- `TestNotesWorkspace` (a signed unlinked DM notes its team; Slack off notes nothing; a repeat claim notes nothing new).
  - `Test/Core/SettingsSlack.cls` (new; shadow `SettingsOpsProbe`) -- `TestListThroughHandoff`, `TestLinkAuditsFirst`, `TestLinkReasons` (bad_member, user_unknown, no_workspace, member_taken, user_taken; no audit, no row), `TestLinkTargetsForUserSession` (two Session rows for one user → the oldest), `TestUnlink`, `TestUnlinkUnknownRef`, `TestNotAudited`, `TestOnlineDemo` (each verb `not_available`, handoff discarded, no audit, no row), `TestNoIdsInRecords` (member id and team id in no audit entry, `CommandResult`, `Ens.MessageHeader` body or log row; the target user name only in the audit entry), `TestWebAdminOnly`.
  - `Test/Web/SlackSettingsApi.cls` + `SlackSettingsProbe.cls` (new; HookSettings/Roles probe pattern) -- `TestRoutes` (GET/POST/DELETE map to the verbs), `TestBodyShape`, `TestRefusalTexts` (each reason → its catalog text, `{user}` filled), `TestNotAdmin`, `TestViewer`, `TestOnlineDemo` (every route 409 `slackOffOnDemo`, nothing submitted), `TestHandoffDiscarded`.
  - `Test/Msg/Contracts.cls` -- the three verbs in the verbs list and their contract entries. `Test/Core/CommandsRouting.cls` -- `TestSlackVerbsWebAdminOnly` (from `web_user`, `tool`, `telegram`, `system` → `not_allowed`).
  - `web/scripts/slack-view.test.mjs` (new) -- `SLACK_TEXTS` and `CHAT_TEXTS.viaSlack` equal the Core catalog texts word for word; `memberIdProblem`; `slackOutcome`; `channels-section.ts` has no static import of `./slack-section` and one `import('./slack-section')`.
  - `web/scripts/chat-view.test.mjs`, `web/scripts/ux-strings.test.mjs` (CONTENDED, gate e) -- `viaSlack` in the deep-equal and a `slack` caption case; `SLACK_TEXTS` in `IMPORTED`, its strings and "via Slack" under `ux`.
  - `web/e2e/api/slack.spec.ts` (new; `live:sign-in`) -- README admin GET/POST/DELETE (workspace seeded with `irisScript` `NoteWorkspace("T0E2E0001")` and removed after); each refusal reason over HTTP (`user_taken` with a second user: the LIVE user signs in first so it has a session); unknown ref 404; no-workspace 400 before seeding; the LIVE OcuTalonUser gets 403 on every route and changes nothing; an `irisScript` scan finds the member id in no audit entry. Second-session isolation: not applicable (an install-wide admin setting, not session-owned data).
  - `web/e2e/settings/slack.spec.ts` (new; `live:sign-in-2`) -- Settings › Channels › Slack region: off state (default stack) with the How-to link `href` ending `GUIDE.md#slack`; empty list text; link the README user (workspace seeded), row appears, unlink, row gone; a bad member id shows `slackBadMemberId` with no request; `page.route` 409 → only `slackOffOnDemo`; `page.route` GET `state:"on"` → `slackOn` and the address on this origin.
  - `web/e2e/chat/via-slack.spec.ts` (new; `live:sign-in`) -- a seeded Turn of channel `slack` shows the caption "via Slack" (`seedTurns` as `chat.spec.ts:560-573`).
  - `docker/tests/test-slack-hook.sh` -- phase 2 links through the real route: sign in as the README admin with curl, `GET` (state `on`, the path), a signed DM from the fixture member before linking (Ignored, workspace noted), `POST` the link for the README user; phase 3's DM then becomes the Turn as today; a new last phase `DELETE`s the link and a further DM leaves no new Turn; the leak scan also covers the audit for the member id.

**Acceptance Criteria:**
- Given Story 27.1's route, `SlackIn` and its link table, when this story lands, then the spine says how an admin links a Slack member to an OcuTalon user and carries DW-1442's AD-13, AD-14, AD-17 and AD-22 wording fixes exactly as the Planner ruled gate item (f), and `lint_spine.py` reports `"ok": true` (AD-14, AD-19, AD-29, AD-33; DW-1442).
- Given the approved R12 texts, when the change is read, then each `settings.slack*` key and `chat.viaSlack` is in `Msg.Catalog.Core` and in `EXPERIENCE.md`'s Message Catalog word for word, the four setup steps are in `EXPERIENCE.md` Later Steps and `GUIDE.md` › Slack word for word, and the page's strings equal the catalog's (`slack-view.test.mjs`, `ux-strings.test.mjs`, `Test.Msg.Catalog`) (UX-DR117).
- Given a README admin on a stack with Slack on, when they link a member to a user through `POST /api/v1/settings/channels/slack`, then one audit entry precedes the row, and `SlackIn` (the consumer) turns that member's next signed direct message into exactly one Turn of channel `slack` in the user's session; after `DELETE`, the next one makes no Turn (Integration AC; `live:slack-hook`, real production).
- Given each row of the I/O matrix, when it is exercised through the real hook and web applications (`web/e2e/api/slack.spec.ts`, `live:slack-hook`) and the probes, then the status, body, message and side effects match the row.
- Given the Settings page, when an admin opens Channels, then the Slack group renders from a lazy chunk with the state the list returned, the members list and the form, and `initial-bundle.test.mjs` passes at its unchanged cap (`web/e2e/settings/slack.spec.ts`, `slack-view.test.mjs`).
- Given the online-demo flag, when any Slack settings route or verb is called, then it answers `not_available` with `settings.slackOffOnDemo`, submits, audits and stores nothing, and the page shows only that line (`SlackSettingsApi.TestOnlineDemo`, `SettingsSlack.TestOnlineDemo`, the e2e 409 case).
- Given a link, list or unlink, when it completes or is refused, then no member id or team id is in any traced message, result, log or audit entry, and no user name other than the admin's is in a traced message (R8, AD-24; `SettingsSlack.TestNoIdsInRecords`, the e2e and live leak scans).
- Given a Turn of channel `slack` in the web chat, when it renders, then its caption is "via Slack" (`chat-view.test.mjs`, `web/e2e/chat/via-slack.spec.ts`).

- Given a workspace already noted in `^OcuTalonP.SlackW` and a link in it, when a signed event arrives from a SECOND team (a direct message from the same member id, and one from an unlinked member id), then no `Data.SlackLink` row is created or changed (row count, every row's TeamId/MemberId/SessionRef unchanged), and the event is Ignored under R2 (Contest Planner ruling 2026-11-16, PIN; e.g. `SlackIn.TestSecondTeamChangesNoLink` plus a live phase-3 check).

## Spec Change Log

- 2026-11-16 ~20:40Z, lead: Contest Planner gate rulings (prompts/story-273-rulings-20261116.md, outside the repo) applied. APPROVED: the two new texts (`settings.slackNoWorkspace`, `settings.slackUnknownUser`) and the GUIDE `## Slack` heading verbatim; all veto items; the linking design; Task 0's grant check (STOP if a new grant would be needed); proceed NOW on the contended `SettingsOps` Carry lines and the chat-view / ux-strings inserts (whichever branch lands second re-runs its web tests after the merge); the spine edits exactly as in Design Notes › Planner gate items (f), including DW-1442's AD-13/14/17/22 and AD-33 fixes and the linking additions. Two additions: (1) Design Notes records the one-workspace-per-install limit; (2) a new acceptance criterion pins that an event from a second team creates or changes no link. At PART READY the lead reports the catalog key count (161 + R12's + 2) with the list of added keys.

## Review Triage Log

## Design Notes

**Governing ADs:** AD-1 (three new `web_admin`-only verbs to `SettingsOps`), AD-4 (identity only in its own row), AD-13 (the web process reads no stored row; DW-1442 hook wording), AD-14 (DW-1442), AD-17 (audit first, `Settings` entries; V4 allows the IRIS user name; DW-1442), AD-19 (env-only Slack config, no setting key), AD-22 (DW-1442), AD-24 (personal data through `SecretHandoff`; `OcuTalonWebhook` grants unchanged), AD-25 (online demo), AD-27 (retention: links go with their session), AD-29 and AD-33 (Lane B ownership; contended appends). No AC contradicts an AD Rule; DW-1442's fixes align the wording with 27.1's shipped behaviour.

**Decided in-stage:**
1. Which session: a link goes to `Data.Session.ForUser(user)`, the user's one durable session on a local install (the row every later sign-in reuses, `Ownership.Attach`). Only users with a Session row can be linked (the `OnCallUsers` roster, Rule 2: reused); a user who never signed in is refused `user_unknown` and is not offered by the picker. A later sign-in reuses the same row, so the link holds. If the row is purged (idle past retention: no turn, no sign-in, no other keep reason), the link goes with it (R8) and the admin re-links after the user's next sign-in.
2. Team id without calling Slack: `SlackIn` notes the `team_id` of each signed event in `^OcuTalonP.SlackW` (one value, overwritten when it differs; setup step 1 installs the app to one workspace). `LinkSlackMember` uses it and refuses `no_workspace` until one is noted (the person sends the bot a direct message first). Rejected: a `SLACK_TEAM_ID` env var (changes the approved setup step 2 and `.env.example` text); a team learned per link at the first DM (weakens R2). Veto item (c).
3. Two refusals: `Data.SlackLink.Taken` before the audit entry, plus a `reason` output on `Link` for a race; both in Lane B's own file (extends, no copy).
4. Retention: a link is not a keep reason for the AD-27 purge. Adding it to `Keeps` would keep a removed user's session and link for good, against R8 ("the AD-27 purge ... deletes a removed user's link rows"), and needs the contended `Purge.cls`. A linked member who messages keeps the session alive through its Turns. No orphan purge: the cascading foreign key makes an orphan link impossible outside a `%NOCHECK` test delete.
5. Unlink by the link's opaque `Ref` (in no message as an identifier of a person), so it needs no handoff; link and list use the handoff because they carry a user name and a member id.
6. The audit entry names the linked IRIS user (`from`/`to`), as roles do (AD-17 V4), and never the member or team id; setting `slackLink.<Ref>`.
7. Member ids are trimmed and upper-cased, then must be `U` or `W` followed by 2 to 31 letters or digits (within `IDMAX` 32).
8. Slack's state is computed in the production job inside `ListSlackLinks` from `SlackIn.On()`; the members part shows in both states (links survive a restart without the env values).
9. Result messages carry no names: the route renders each text, filling `{user}` in its own process.
10. "How to set it up" links to `GUIDE.md#slack` (new tab), as Telegram's links to its README section; this story writes that GUIDE section with only the approved steps. Story 27.2 owns the README developer section.
11. The Slack group is created lazily from `channels-section.ts`, which is not contended; its texts live in `slack-view.ts` (precedent `ROLES_TEXTS`), so `settings-view.ts` is not edited.
12. `&amp;`/mention-markup decoding of turn text stays with Story 27.2 (the reply story), as the epic context allows.
13. Rule 2 (extend, don't copy): `Link`, `Unlink`, `On()`, `ForUser`, `OnCallUsers`, `AuditData`/`WriteAudit`, `HandOff`/`Submit`, `WebhookFieldText` and `readmeSection` are reused as they are. Copies with their reason: `Web.SlackSettings` follows `Web.RoleSettings`' shape (a `%CSP.REST` forward target cannot share another target's routes); `slack-section.ts`/`slack-view.ts` follow the webhooks section's state machine (different fields, outcomes and texts; no shared base component exists); `Test.Core.SettingsSlack` and `Test.Web.SlackSettingsApi` follow `SettingsWebhooks` and `HookSettingsApi` and reuse their probes where the seams exist.
14. CI: no new unit and no new test area. The two new e2e files join `live:sign-in` (`api/`, `chat/`) and one joins `live:sign-in-2` (`settings/`), adding a few tests each; `live:slack-hook` (`shards-3`) gains about 20 to 30 s (inference); the implement stage reports the measured times.
15. Size: one cohesive cross-layer story (the shape of Story 35.3's webhooks). A split of the Settings UI and marker into a sibling was considered and rejected: the UI is this story's "As an admin, I want to see in Settings" and 27.2's README describes it.

**Integration ACs / Consumed-by / Consumes:**
- Consumes: `Data.SlackLink` (`Link`, `Unlink`, `SessionFor`), `SlackIn.On()`, `Data.Session.ForUser`, `SettingsOps.OnCallUsers`, `Core.SecretHandoff`, `Bridge.Audit` (through `WriteAudit`).
- Integration AC: `SlackIn` reads the link the admin route wrote and produces a Turn (AC 3, `live:slack-hook`, real production); the Slack group reads `GET /api/v1/settings/channels/slack` and renders the state and list (AC 5, `web/e2e/settings/slack.spec.ts`).
- Consumed-by: Story 27.2 (its README linking section describes this UI; `SlackOut` replies to linked members' turns).

**Limit (Contest Planner ruling 2026-11-16): ONE WORKSPACE PER INSTALL.** `^OcuTalonP.SlackW` holds one team id. If it changes (the install's Slack app is moved to another workspace), every earlier link stops matching under R2 (team id AND member id), by design; links are not migrated or rewritten.

**Model-facing check:** none. The new texts are web-only (Settings, the chat caption); `^OcuTalonP.SlackW` is read only by `SettingsOps`; no prompt, tool description, INSTRUCTIONS block or notes line changes (R7 untouched).

**Ledger inbox:** DW-1442 is addressed by the spine task and AC 1, with the exact wording in gate item (f).

### Planner gate items: ruled 2026-11-16 (all approved; prompts/story-273-rulings-20261116.md)

- (a) PUBLIC TEXT.
  - Approved R12, shipped verbatim: `settings.slackHeading`, `slackNotSetUp`, `slackHowTo`, `slackOn`, `slackAddress`, `slackOffOnDemo`, `slackMembersHeading`, `slackMembersHelp`, `slackMemberId`, `slackMemberUser`, `slackLink`, `slackUnlink`, `slackNoMembers`, `slackBadMemberId`, `slackMemberTaken`, `slackUserTaken`, `slackLinked`, `slackUnlinked`, `chat.viaSlack`, and the four reordered setup steps (27.1 spec, gate a).
  - NEW, for a ruling: `settings.slackNoWorkspace` "OcuTalon hasn't had an event from your Slack workspace yet. Ask the person to send the bot a direct message, then link them. Nothing was changed."
  - NEW, for a ruling: `settings.slackUnknownUser` "Choose an OcuTalon user from the list. Nothing was changed."
  - NEW, for a ruling: the `GUIDE.md` heading "Slack" (`## Slack`) over the four approved steps, with no other sentence.
  - Reused unchanged (existing public text): `MESSAGEBADSETTINGS`, `MESSAGENOTFOUND`, `MESSAGESERVERERROR`, `MESSAGENOTADMIN`, the webhooks section's load-failed and retry texts, the opens-in-new-tab text.
- (b) Outward actions: none. No call to slack.com; tests use dummy ids and curl to the throwaway.
- (c) Veto items, each with its online-demo behaviour:
  - Routes `GET`/`POST /api/v1/settings/channels/slack` and `DELETE /api/v1/settings/channels/slack/<ref>`, admin only. Demo: 409 `not_available` before anything is read.
  - Command verbs `ListSlackLinks`, `LinkSlackMember`, `UnlinkSlackMember`, origin `web_admin` only, to `SettingsOps`; not tool verbs; never from a Slack sender. Demo: `not_available`.
  - Stored data: `^OcuTalonP.SlackW`, one workspace `team_id` noted by `SlackIn` from signed events (overwritten on change, removed with the package's globals). Demo: never written (Slack is off, `SlackIn` refuses).
  - Retention: a link is no keep reason; it goes with its session (R8 as ruled); no `Keeps` line, no orphan purge. Demo: no links exist.
  - Privileges: no new role, resource or grant; the admin check is the existing `OcuTalonAdmin` one; the LIVE OcuTalonUser and viewers are refused 403. `SlackIn`'s write to `^OcuTalonP.SlackW` runs under `OcuTalonWebhook`'s existing grants (Task 0 proves it or HALTs). Demo: unchanged.
  - Personal data: the admin sees member ids and user names in Settings through the handoff; the audit names the linked IRIS user (AD-17 V4), never a member or team id. Demo: nothing stored.
  - Secrets: none new.
- (d) Model-facing text changes: none.
- (e) Contended paths:
  - `src/ocutalon/cls/OcuTalon/Web/Api.cls` (Lane D, 24.3): one line `<Map Prefix="/v1/settings/channels/slack" Forward="OcuTalon.Web.SlackSettings"/>` after the `/v1/settings/mcp` Map line (one-name append, reported). Need not wait.
  - `src/ocutalon/cls/OcuTalon/Core/SettingsOps.cls` (Lane A, 25.9): three `If class = "OcuTalon.Msg.Command.<Verb>" Quit ..<Method>(command)` lines in `Carry` before the `unknown_command` line, and one self-contained block of new methods appended at the end of the class. The `Carry` lines are not an append: ruling asked; recommended to proceed now (three adjacent lines; a merge with 25.9 resolves them textually).
  - `web/src/app/chat/chat-view.ts` (Lane D, 24.3): `viaSlack: 'via Slack',` after the `viaTelegram` line, and `if (channel === 'slack') return CHAT_TEXTS.viaSlack;` after the telegram line of `captionOf`. Two inserts: ruling asked; recommended to proceed now. If ruled to wait, the marker tasks (this file, `chat-view.test.mjs`, `via-slack.spec.ts`, the `ux-strings` "via Slack" entry) land after OCT-epic24 merges and the rest ships.
  - `web/scripts/chat-view.test.mjs` (Lane D): `viaSlack: 'via Slack'` in the `CHAT_TEXTS` deep-equal and one `slack` caption case. Same ruling as `chat-view.ts`.
  - `web/scripts/ux-strings.test.mjs` (Lane D): `SLACK_TEXTS` appended to `IMPORTED`, and one appended block of `ux` entries (the Slack strings and "via Slack"). Append only; reported.
  - `Test/Core/SettingsOpsProbe.cls` (Lane A, 25.9): used, not edited; the new `Test/Core/SettingsSlack.cls` is a new file in a contended folder (reported).
  - Not edited: `Data/Purge.cls`, `settings-view.ts`, `on-call-section.ts`, `Production.cls`, `Test/Data/Tables.cls`, Epic 28's paths, any Telegram class.
- (f) Spine edits (`ARCHITECTURE-SPINE.md`, written by the implement stage only after the ruling; tag each `[AMENDED <the date written>, Story 27.3, DW-1442, Contest Planner ruling]` (AD-13, AD-14, AD-17, AD-22, AD-33) or `[ADDED <the date written>, Story 27.3, Contest Planner ruling]` (the linking edits)):
  - DW-1442, AD-13 (:490): "Order: an unknown `Ref`," → "Order for `/<ref>`: an unknown `Ref`,"; "A valid request goes to `WebhookIn`" → "A valid request to `/<ref>` goes to `WebhookIn`"; "and hand the event to `WebhookIn`" → "and hand the event to `WebhookIn`, and on the Slack route what `SlackIn` needs (AD-24)".
  - DW-1442, AD-14 (:528): "Every inbound message becomes an `OcuTalon.Msg.Item`" → "Every inbound message a channel accepts becomes an `OcuTalon.Msg.Item`"; after "… and content." add "A Slack event that is not a linked member's direct message becomes no Item: it leaves one content-free `Ignored` record (AD-13's Slack route, AD-26)."
  - DW-1442, AD-17 (:636): "Rejected webhook requests are audited at a capped rate." → "Rejected webhook and Slack requests are audited at a capped rate."; at the end of :637 add "Rejected Slack requests (Story 27.1) are the same entries with target `slack`, one slot for all of them, under the same cap."
  - DW-1442, AD-22 (:960): after "… and the row (`DropEval`)." add "A notes case of the R7 knob (Story 27.1; `eval/run.sh --notes <channel>` over `eval/notes-cases/`, outside the main and held-out sets) also gets an eval-only `Session` row whose notes are `Turn` rows written only by `Data.Turn.ForEval` (refused unless `OCUTALON_EVAL` is 1, the session `IsEval` and the channel a `CHANNEL` value) and deleted by `DropEval` with the row."
  - Companion to DW-1442, AD-33 (:1325): after "called only by `EvalIn` (`docker/tests/test-boundaries.sh` pins it)," add "and from Story 27.1 `Data.Turn` gains `ForEval`, called only by `EvalIn` (the same pin), whose rows `DropEval` deletes,".
  - Linking, AD-1 (after :131): "- From step 7 (Story 27.3) `CommandsIn` also accepts `ListSlackLinks`, `LinkSlackMember` (`Handoff`, `ActingUser`) and `UnlinkSlackMember` (`LinkRef`, `ActingUser`) from origin `web_admin` only, to `SettingsOps`; none is a tool verb or a verb of a Slack sender, and the user name and member id travel only in the `SecretHandoff` (AD-24)."
  - Linking, AD-24 Personal data (after :1066): "- The Slack section (Story 27.3) hands the user name and the member id to `SettingsOps` through `SecretHandoff`, and `ListSlackLinks`' list (links and linkable users) comes back the same way; its `Settings` audit entry names the linked IRIS user, never a member or team id (R8)."
  - Linking, Tables paragraph (:1577), after the `SlackLink` parenthesis: "An admin links a member in Settings › Channels › Slack (Story 27.3): `SettingsOps` links the member id to the user's one durable session (`Data.Session.ForUser`, for a user who has a session row) under the workspace `team_id` that `SlackIn` notes from signed events in `^OcuTalonP.SlackW` (one value, overwritten on change, never sent anywhere); a link is no keep reason for the AD-27 purge and goes with its session (R8)."
  - REST surface (after :1837): `| GET /api/v1/settings/channels/slack, POST /api/v1/settings/channels/slack and DELETE /api/v1/settings/channels/slack/<ref> | Slack's state (from SlackIn.On()), the linked members and the linkable users through SecretHandoff; a link of a member id to a user; an unlink by the link's Ref; OcuTalon.Web.SlackSettings, forwarded from OcuTalon.Web.Api, admin only, through SettingsOps; on the online demo every route is 409 not_available (Story 27.3) |`.

## Verification

All commands from the worktree root. `LANE` below means `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-b" OCUTALON_TEST_WEB_PORT=52802 OCUTALON_LOCK_OWNER='epic=27 stage=implement'`. Each command is one foreground call with `timeout: 600000`; one test-runner call per message.

**Commands:**
- (once) `LANE OCUTALON_RUN_TAG=e27s3iw ci/warm.sh up` -- expected: a warm lane-B stack.
- (loop) `LANE OCUTALON_WARM=1 OCUTALON_RUN_TAG=e27s3iw ci/iris.sh class <Class>`, one class per call, for `OcuTalon.Test.Data.SlackLink`, `.Test.Channel.SlackIn`, `.Test.Core.SettingsSlack`, `.Test.Web.SlackSettingsApi`, `.Test.Msg.Catalog`, `.Test.Msg.Contracts`, `.Test.Core.CommandsRouting`, `.Test.Channel.SlackHook`, `.Test.Web.Hook` -- expected: `CLASS ... passed`.
- (once) `LANE OCUTALON_RUN_TAG=e27s3iw ci/warm.sh down` -- also after a failure.
- (loop) `node --test web/scripts/slack-view.test.mjs web/scripts/chat-view.test.mjs web/scripts/ux-strings.test.mjs web/scripts/webhooks-view.test.mjs` -- expected: all pass.
- (once) `node --test web/scripts/initial-bundle.test.mjs web/scripts/lazy-routes.test.mjs` -- expected: pass, initial bytes under 921,000 (record before and after).
- (once) `bash docker/tests/test-class-rules.sh` -- expected: `web-global-reads` and every rule pass.
- (once) `LANE OCUTALON_RUN_TAG=e27s3i ci/iris.sh build` then (once, separate call) `LANE OCUTALON_RUN_TAG=e27s3i ci/iris.sh live slack-hook` -- expected: every phase PASS (about 5 minutes).
- (once) `LANE OCUTALON_RUN_TAG=e27s3i ci/iris.sh live sign-in --part k/n`, with `k/n` the part whose `SPEC` lines hold `api/slack.spec.ts` and `chat/via-slack.spec.ts` (one call per part needed) -- expected: pass.
- (once) `LANE OCUTALON_RUN_TAG=e27s3i ci/iris.sh live sign-in-2 --part k/n`, the part holding `settings/slack.spec.ts` -- expected: pass.
- (once) `LANE OCUTALON_RUN_TAG=e27s3i ci/iris.sh teardown` -- removes only this tag's projects.
- (once, after the ruling) `uv run --no-cache .claude/skills/bmad-architecture/scripts/lint_spine.py --workspace _bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16` -- expected: `"ok": true`, no finding beyond the 13 pre-existing low placeholders.

**Shared surfaces:** the Core catalog key count and `XData Keys`/`Fixtures` of `Test.Msg.Catalog`; the verbs list of `Test.Msg.Contracts`; `CommandsIn`'s Routes table; `CHAT_TEXTS` (deep-equal in `chat-view.test.mjs`) and the initial bundle's bytes; `ux-strings.test.mjs` `IMPORTED`/`SOURCES`; the Settings › Channels DOM (`web/e2e/settings/*.spec.ts` that count its groups); `Api`'s UrlMap; the phases and leak scan of `live:slack-hook`; `^OcuTalonP.SlackW` (tests that create it remove it).

**Standing criterion (Rule 19):** every test added or changed passes on a fresh environment, in either order. The lead's fresh check runs `shard lane-a@Channel` and the `lane-b` pieces holding `Data`, `Core`, `Web` and `Msg` forward and with `--reverse`.

**Planned mutations (one per AC; the implement stage records each as `mutation: … → …`):**
- AC 2: change one word of `settings.slackLinked` in `Core.cls` → `slack-view.test.mjs` parity red.
- AC 3: drop the `NoteWorkspace` call in `SlackIn` → `live:slack-hook` link refused `no_workspace` (and `SlackIn.TestNotesWorkspace` red).
- AC 4: return `member_taken` for `user_taken` in `SettingsOps.LinkSlack` → `SettingsSlack.TestLinkReasons` and `api/slack.spec.ts` red.
- AC 5: import `./slack-section` statically in `channels-section.ts` → `slack-view.test.mjs` lazy check red.
- AC 6: remove the demo check from `SlackSettings.Refusal` → `SlackSettingsApi.TestOnlineDemo` red.
- AC 7: put the member id in the audit `to` value → `SettingsSlack.TestNoIdsInRecords` red.
- AC 8: drop the `slack` branch of `captionOf` → `chat-view.test.mjs` caption case red.
- AC 1: none (a document edit, checked by `lint_spine.py` and the reviewer against gate f).

**Task 0 record:** (filled by the implement stage).

## Auto Run Result

Status: ready-for-dev
Blocking condition: none

- Plan stage (2026-11-16): planned against the delivered 27.1 code on `OCT-epic27` at `4324facb44f782bdbfc0e9f701de2b4251ea0637`; halted after planning as dispatched. The build waits for the Planner's ruling on `### Planner gate items` (a) new public text, (c) veto items, (e) contended paths and (f) spine edits including DW-1442.
