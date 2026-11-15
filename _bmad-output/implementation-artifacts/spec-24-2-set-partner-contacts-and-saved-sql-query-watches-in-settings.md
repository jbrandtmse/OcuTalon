---
title: 'Story 24.2: Set partner contacts and saved SQL query watches in Settings'
type: 'feature'
created: '2026-11-15'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-24-context.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-36-4-set-the-on-call-person-and-backup-in-settings.md'
warnings: ['multiple-goals', 'oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** Story 36.2 named the partner-contact table, the `partner-contacts` and `sql-watches` settings sections and the `SaveSqlWatch` verb, but nothing writes or shows any of them. Partner warnings (23.5) still read a demo-only fixture. An admin has no way to save a SQL query watch.

**Approach:**
- Add `OcuTalon.Data.PartnerContact` with its only writer, a `contacts` saver in `SettingsOps`. Contact values reach it only through `SecretHandoff`, as 36.4's on-call body does (DW-1254), and their reader is `ForProduction`.
- Add `Web.PartnerSettings` and `Web.SqlWatchSettings`, two forwarded admin-only routes.
- Add two Settings sections. The SQL section submits `SaveSqlWatch` to `WatchOps` and stays hidden (the route answers `not_built`) until Lane A's 23.8 makes `WatchOps` handle the verb. Tests use a fixture `WatchOps`.
- This plan follows gate recommendations G1-A and G2-a (Design Notes). The gate may still choose otherwise.

## Boundaries & Constraints

**Always:**
- `SettingsOps` is the only writer of `PartnerContact`.
  - It validates the whole body before writing anything.
  - Each changed field gets its own `Settings` audit entry, written through `Bridge.Audit.Record` before the row and in the same transaction, which a failure rolls back.
  - The audit setting is `partnerContact.<Ref>.name`, `.email` or `.productions`. Each entry holds from and to, the admin's IRIS user, the session Ref and channel `web`.
  - A removal audits each field to "".
- Partner values travel only through `SecretHandoff`.
  - `Web.PartnerSettings` offers the body before the submit and discards it on every path.
  - `SaveSettings.Changes` is exactly `{"handoff":"secret://handoff/<name>"}`.
  - A refusal names fields only. No name or address is in a command, a `CommandResult`, a log line, a trace or a notice. Values reach only the row and the IRIS audit entry.
- `SaveSqlWatch` goes only through `Commands.Submit` with origin `web_admin` (AD-1). The route never writes `BackgroundCheck`.
- Admin only: 403 `not_admin` (Api `OnPreDispatch` and each route).
- Online demo:
  - Both routes answer 409 `not_available` (`settings.partnersOffOnDemo` / `settings.sqlOffOnDemo`) before reading the body.
  - `SettingsOps` also answers `not_available`, and nothing is written.
  - `GET /v1/settings` has neither member, and the page hides both sections.
- Ship only accepted texts, verbatim, plus any NEW text the Planner accepts (`## Public text`). Strings go in `SETTINGS_TEXTS.partners` and `SETTINGS_TEXTS.sql`, with `ux-strings.test.mjs` SOURCES entries.
- Every IRIS test runs on a lane-D throwaway (`ci/iris.sh`, `ci/warm.sh`), never on a slot. Tests create and remove their own contacts, sessions and fixture check rows.

**Never:**
- Do not edit Lane A files: `Watch/Ops.cls`, `Fix/**`, `Watch/IncidentManager.cls`, `Data/BackgroundCheck.cls`, `Msg/Catalog/*.cls`. 24.2 never switches 23.5's reader (G2).
- No change to `Core/SecretHandoff.cls`, `README.md`, `GUIDE.md`, the More to try registry, `ci/units.sh`, `.github/workflows` or `release/**`.
- No role, grant, resource or new Web application. Never widen `OcuTalonUser`.
- Do not send any email or notice. Do not put a partner value into a `$$$LOG*` text or a status text.
- Do not claim that the SQL user only reads (the condition on `settings.sqlHelp`).

## I/O & Edge-Case Matrix

The partner body is `{action, ref, name, email, productions}`:
- `action` is `save` or `remove`;
- `ref` is "" for a new contact;
- `productions` is `[{namespace, production}]`, each an entry of `Watch.Reader.Productions()` read in the production job when the save runs.

A remove needs `{action, ref}` only.

The SQL body is `{action, ref, name, query, intervalMinutes}`.

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Add contact | save, ref "", name ≤128 chars after trimming, address that `SettingsOps.IsAddress` accepts (≤254), one or more productions | Row inserted (`CreatedAt`/`UpdatedAt` UTC); 3 audit entries from ""; 200 with sections | none |
| Edit | save, an existing ref, changed fields | Only the changed fields audited; `UpdatedAt` set | none |
| Nothing changed | save with the stored values | 200 done; no audit entry, row untouched | none |
| Remove | remove, an existing ref | Row deleted; 3 audit entries to "" | none |
| Bad fields | name "" or >128 chars or containing `@{` or a control char; bad address; `productions` [] or containing an entry that is not current or is repeated | 400 `bad_settings` naming `name`/`email`/`productions`; nothing written or audited | page: `partnerBadName`, `badEmail`, `partnerNoProduction`; focus on the first |
| Shape | missing/extra member, wrong type, unknown action, unknown ref, body not an object | 400 `bad_settings` with `[]` | page: "Couldn't save. Nothing was changed." |
| SQL not built | `WatchOps`' compiled MessageMap has no `SaveSqlWatch` (feature today) | GET has no `sql-watches`; POST 501 `not_built`, nothing submitted | page hides the section |
| SQL save (fixture) | built; name 1-128; query 1-4000; minutes a whole number 1-1440 | one `SaveSqlWatch` {save, "", name, query, minutes}; 200 `{result, message, watches}` with the owner's Message | none |
| SQL refused (fixture) | owner answers Ok 0 (any outcome but failed/not_built) | 400 `bad_sql_watch` `{query: <owner's Message>}` | shown under Query |
| SQL bad shape | name bad / minutes not 1-1440 / query "" or >4000 | 400 `bad_sql_watch` `{name: sqlBadName}` / `{intervalMinutes: onCallBadMinutes}` / form error; nothing submitted | field error |
| SQL remove | remove, ref of the caller's own `sql_query` row | one `SaveSqlWatch` {remove, ref}; 200 | another session's/kind's/unknown ref: 404, nothing submitted |
| Non-admin / demo | `OcuTalonUser`; `onlineDemo` 1 | 403 `not_admin`; 409 `not_available` with the off text | as Always |
| Server failure | submit error, a throw, `failed`, `not_audited` | 500; handoff discarded | "Couldn't save. Nothing was changed." |

</intent-contract>

## Code Map

- `src/ocutalon/cls/OcuTalon/Core/SettingsOps.cls` -- the writer.
  - `Carry` L197 (verb branches).
  - `XData Sections` L906-946: the `on-call` row ends it; append `{"slug":"partner-contacts","kind":"contacts","fields":[]}`.
  - `Values` L971: the kind skip L976; the on-call line L995.
  - `Save` L1039: the `oncall` dispatch L1049.
  - `Refused` L1074.
  - `SaveProduct` L1128: the audit-then-write transaction to mirror. It cannot be reused, because it writes `Setting` keys through `Apply`.
  - `AuditData` L250, `WriteAudit` L271 (probe seam), `IsAddress` L1929, `HasControl` L1947.
  - `TakeSecret` L2362 (`HANDOFFWAIT` 2 s).
  - `SaveOnCall` L2538: its handoff prologue (demo discard, exactly `{handoff}`, take, parse), which becomes the shared helper.
  - `ListOnCallUsers` L2710 and `OnCallRoster`/`SubmitRoster` L2731-2766: the read-verb pattern for `ListProductions`.
  - `OnCallValues` L2768. The class ends at L2786.
- `src/ocutalon/cls/OcuTalon/Web/OnCallSettings.cls` (87 lines) -- the parent of `Web.PartnerSettings`: `Refusal` L29, `Save` L37, `Hand` L52, `Offer` L77 and `Submit` L83 (seams).
- `src/ocutalon/cls/OcuTalon/Web/McpSettings.cls` -- the sibling for SQL watches: `SetSource` L140, `RemoveSource` L167, `OwnSource` L187 (`Ownership.Checks` own-row check), `Answer` L253, `BadSource` L295.
- `src/ocutalon/cls/OcuTalon/Web/Api.cls` -- Maps L313-316 (add two after on-call); class comment L121-126; `Settings` L982 calls `Values()`; `MESSAGENOTADMIN` L204; `IsSettingsUrl` L425 already covers both paths.
- `src/ocutalon/cls/OcuTalon/Core/CommandsIn.cls` -- `Routes` (`SaveSqlWatch` L379 → WatchOps, web_admin); `Send` L190 bounded-wait list; `#MESSAGENOTBUILT`.
  - The class comment has a ListOnCallUsers bullet to mirror.
  - The real answer today is in Design Notes › 23.8 finding.
- `src/ocutalon/cls/OcuTalon/Msg/Command/SaveSqlWatch.cls` (Story 36.2: `Action` save|remove, `CheckRef`, `Name`, `Query` 4000, `IntervalMinutes`). It is the only verb for both save and remove, and is used unchanged.
- `src/ocutalon/cls/OcuTalon/Msg/Command/ListOnCallUsers.cls` -- the sibling of NEW `ListProductions`.
- `src/ocutalon/cls/OcuTalon/Watch/Reader.cls:113` `Productions()` -- `[{namespace, production, displayName, state}]`. It needs the production job (it reads the `ServiceUser` setting), so the web process gets the list through `ListProductions`. Read only (Lane A).
- `src/ocutalon/cls/OcuTalon/Watch/Ops.cls` -- `XData MessageMap` L83 maps only `StartWatch` and `StopWatch` today. Read only.
- `src/ocutalon/cls/OcuTalon/Data/Ownership.cls:439` `Checks(sessionRef, .sc)` -- the session's `BackgroundCheck` rows, read from the web (as `Web/Api.cls:1533` and `McpSettings.cls:189` do).
- `src/ocutalon/cls/OcuTalon/Data/Webhook.cls` -- the sibling for `Data.PartnerContact`: Lane B, `DEFAULTGLOBAL` from `src/short-names.tsv` (row L37), object access only.
- `src/ocutalon/cls/OcuTalon/Fix/PartnerContacts.cls` -- Lane A's demo fixture, which 23.5's `IncidentManager` L1133/L1289 and `Fix/Kind/PartnerWarning.cls` L68/L196/L263 read. Its `For` shape is `[{id (positive whole number), name, address}]`, and `ForProduction` returns the same shape. Read only.
- Web:
  - `web/src/app/settings/settings-view.ts`: `SETTINGS_TEXTS.sections` L44 and the `onCall` block L95; `SETTINGS_SECTIONS` L159, where both new slugs go after `on-call`.
  - `settings-page.ts`: on-call imports L20, `@case` L70, and the hide-when-absent rule L255-261 (generalize it to the three slugs), `keepOnCall` L350.
  - `on-call-section.ts` and `on-call-view.ts`: the form, error, focus and announce pattern.
  - `mcp-section.ts`: the source list L344-378, the confirm dialog L848-875 (`MCP_TEXTS.cancel`, `SETTINGS_TEXTS.failed`) and Remove-at-once L822.
  - `api/api-client.ts:66` `saveSettings` (unchanged) and L139-146 (`setMcpSource` and `removeMcpSource` show the shape); `api/api-types.ts` (`SettingsSections`).
  - `rail/rail-view.ts`: `intervalText` L174 and the result word `resultWord` L299 (reused for the SQL list's Schedule and Last result); `checkTitle` L241 already titles any non-production check by its name.
- Tests to extend:
  - `Test/Core/SettingsOnCall.cls`: the probe and handoff pattern.
  - `Test/Core/SettingsSave.cls:441`: the expected section keys.
  - `Test/Web/OnCallSettingsApi.cls`:
    - L240-283 `TestValuesOnlyInTheAuditLog`: the leak scan to lift into a shared helper;
    - `TableHolds` L419, `Test.Web.WebhookTools` `LastLog`/`LastHeader`/`LogText`, `Test.Core.SecretHandoff` `Leaks`/`TraceLeaks`, `Test.Bridge.AuditLog` `Now`/`Wait`.
  - `Test/Web/OnCallSettingsProbe.cls` (the seams).
  - `Test/Core/CommandsRouting.cls` (`TestListOnCallUsersRouting` and the verb tables L72/L169) and `Test/Msg/Contracts.cls` L42/L62-70.
  - `web/e2e/settings/on-call.spec.ts` and `settings.spec.ts` (S1 `NAV_LINKS_ADMIN`, the section-link counts, O6's seven links), `web/e2e/api/on-call.spec.ts` (real HTTP, `irisScript` fresh-process read), `web/scripts/settings-view.test.mjs`, `settings-refusal-sources.test.mjs` (`SAVING`), `announce-focus-sources.test.mjs`, `ux-strings.test.mjs`.
- Spine `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md`:
  - L130: `SaveSqlWatch` is web_admin only.
  - L642: SQL rows are `sql_query`, and 23.8 adds the query columns.
  - L767-772: the step-5 sections, V3 audit and the handoff.
  - L1221-1222: until 23.8, CommandsIn answers `failed` (inference).
  - L1560: the PartnerContact table, its columns and "not the fixture".
  - L1631: the ListOnCallUsers row.
  - L484: AD-13, where web reads go only through owning-class methods.

## Tasks & Acceptance

**Execution:**
- Task 0 (measure, record under Verification): on a lane-D throwaway, confirm that `SaveSqlWatch` from `web_admin` today answers `Ok 0 failed` with `CommandsIn.MESSAGEFAILED` and writes nothing. Confirm that `SqlBuilt()` reads 0 against feature's `WatchOps` and 1 against a probe whose MessageMap names the verb.
- `src/short-names.tsv` -- append `PartnerContact	^OcuTalonP.PartnerContact	OcuTalon.Data.PartnerContact	B`.
- `src/ocutalon/cls/OcuTalon/Data/PartnerContact.cls` -- NEW `%Persistent` with the spine's columns and committed `Storage Default`.
  - Columns: `Ref` (22, unique index), `Name` (128), `Email` (254), `Productions` (JSON text, MAXLEN 4000), `CreatedAt` and `UpdatedAt` (20). There is no index on `Name` or `Email`.
  - `ForProduction(namespace, production)` gives `[{id, name, address}]` with `id` the row ID, in ID order. A contact matches only when one of its entries matches both values.
  - `List()` gives `[{ref, name, email, productions}]` by upper-cased name, then Ref.
  - `RefOpen(ref)`.
  - Object access only, with no SQL. The class description names `SettingsOps` as the only writer.
- `src/ocutalon/cls/OcuTalon/Msg/Command/ListProductions.cls` -- NEW, a copy of `ListOnCallUsers`' shape (no property). The description says it is a read verb, web_admin only and no tool verb.
- `src/ocutalon/cls/OcuTalon/Core/CommandsIn.cls`:
  - add the route `{"verb":"ListProductions","owner":"SettingsOps","origins":"web_admin"}`;
  - in `Send`, give `ListProductions` the bounded wait (`SendSearch`);
  - add one class-comment bullet and one `Routes` comment line.
- `src/ocutalon/cls/OcuTalon/Core/SettingsOps.cls`:
  - `Carry`: branch `ListProductions` → `ListProductions()`. It answers not_available on the demo. Otherwise it answers Ok 1 `listed` with `Data {"productions":[{namespace,production,displayName}]}`, or failed when `Reader.Productions()` throws.
  - `Sections`: add the `partner-contacts` row. `Values(sessionRef As %String = "")`: skip kind `contacts` in L976, and when not on the online demo add:
    - `partner-contacts` = `{contacts: PartnerContact.List(), productions: ProductionsRoster(), warningsUseThese: (+$Parameter("OcuTalon.Fix.PartnerContacts","TABLE") = 1)}`, where `ProductionsRoster` mirrors `OnCallRoster`: it submits through a `SubmitProductions` seam and answers [] on any failure;
    - `sql-watches` = `{watches: SqlWatchRows(sessionRef)}`, only when `SqlBuilt()` and `sessionRef '= ""`. `SqlWatchRows` extends `SourceRows` L2417: generalize it to `CheckRows(sessionRef, kind, .rows)`, which `SourceRows` then calls. The SQL rows are `[{ref, name, intervalMinutes, lastRunAt, result}]`.
  - `Save`: dispatch kind `contacts` → `SavePartner(command, changes)`.
  - Extract `HandoffBody(changes, offText, .body)` from `SaveOnCall`'s prologue, so that both savers call it and `SaveOnCall`'s behaviour is unchanged.
  - `SavePartner`: the prologue, then `PartnerProblems(body, .row, .odd)` (fields only, never values, with the rules of the I/O matrix; the productions are checked against `Reader.Productions()`), then `WritePartner(command, ref, before, after)`: the per-field audit, then insert/update/delete, in one `TSTART`, with rollback, `not_audited` and `failed` as in `SaveProduct`.
  - `SqlBuilt()`: 1 when the compiled `OcuTalon.Watch.Ops||MessageMap` XData names `OcuTalon.Msg.Command.SaveSqlWatch`. Never throws.
  - Add `MESSAGEPARTNERSOFF` and `MESSAGESQLOFF` (the accepted texts verbatim), and one class-description paragraph.
- `src/ocutalon/cls/OcuTalon/Web/OnCallSettings.cls` -- add `ClassMethod OffText()` returning `MESSAGEONCALLOFF`, used in `Refusal` and `Hand` in place of the literal parameter. Behaviour is unchanged.
- `src/ocutalon/cls/OcuTalon/Web/PartnerSettings.cls` -- NEW, extends `Web.OnCallSettings`.
  - Its own `UrlMap`, `<Route Url="" Method="POST" Call="Save"/>`.
  - `OffText` gives `MESSAGEPARTNERSOFF`.
  - `Save` checks the body shape and types (400 `[]` otherwise), then calls the inherited `Hand` with a `SaveSettings` of slug `partner-contacts`.
- `src/ocutalon/cls/OcuTalon/Web/SqlWatchSettings.cls` -- NEW, extends `Web.Api`.
  - `UrlMap` `<Route Url="" Method="POST" Call="Save"/>`.
  - Order of checks: 403, then 409 (`MESSAGESQLOFF`) before the body, then 501 `not_built` (`CommandsIn.MESSAGENOTBUILT`) when `SqlBuilt()` is 0, then the shape and the matrix's field checks.
  - A remove checks the ref with `Ownership.Checks`: the caller's own row of Kind `sql_query`, else 404.
  - It submits one `SaveSqlWatch` through a `Submit` seam (web_admin, the CSP session's Ref).
  - It answers 200 `{result, message: result.Message, watches}`, the 400 relay, or 500. There is also a `Built()` seam.
- `src/ocutalon/cls/OcuTalon/Web/Api.cls` -- add the Maps `/v1/settings/partner-contacts` → `Web.PartnerSettings` and `/v1/settings/sql-watches` → `Web.SqlWatchSettings`, two class-comment bullets, and `Settings` passes `Ownership.SessionRef` to `Values`.
- Web:
  - `web/src/app/api/api-types.ts`: `PartnerContactsValues`, `SqlWatchesValues`, the bodies, and the members in `SettingsSections`.
  - `api-client.ts`: `savePartnerContact` (POST) and `saveSqlWatch` (POST); the GET is unchanged.
- `web/src/app/settings/settings-view.ts` -- add:
  - `sections.partners` and `sections.sql`;
  - the `partners` and `sql` blocks of accepted texts, plus `partnersNotYet` only if it is accepted;
  - both slugs in `SETTINGS_SECTIONS`, after `on-call`;
  - the header comment.
- `web/src/app/settings/partner-view.ts` and `sql-view.ts` -- NEW, framework-free rules.
  - Partner: `PARTNER_FIELDS` (name, email, productions), `partnerBody`, `isPartnerDirty` and `productionKey`.
  - SQL: `SQL_FIELDS` (name, query, intervalMinutes), `sqlBody` and `watchRow` (the Schedule cell is `intervalText`, Last result is the rail's result word, and Last run uses the rail's `when`).
  - Shared: `fieldErrorText`.
- `web/src/app/settings/partner-contacts-section.ts` -- NEW, built like `on-call-section.ts` and `mcp-section.ts`.
  - The heading, then either `partnersHelp` while `warningsUseThese`, or else the not-yet line if it is accepted (nothing if it is refused).
  - One form per contact, with Name, Email address, a "Productions it concerns" fieldset of checkboxes labelled with each `displayName`, Save changes and Remove.
  - An Add contact form.
  - The Remove confirm (`partnerRemoveConfirm`, `MCP_TEXTS.cancel`) appears only while `warningsUseThese`; otherwise Remove acts at once.
  - 400: mark the fields and focus the first. 403: denied. 409: off text. Other errors: failed.
  - Each row's Save, Remove and fields take accessible names from their label plus the row's name cell (`aria-labelledby`), with no new string.
- `web/src/app/settings/sql-watches-section.ts` -- NEW: the help, an add form (Name, Query textarea maxlength 4000, "Check every" with the "minutes" unit, Save query), and a table (Name, Schedule, Last run, Last result, Remove at once). It announces `message` and shows a 400 relay under its field.
- `web/src/app/settings/settings-page.ts` -- import and `@case` both sections. Generalize the on-call hide rule to `['on-call','partner-contacts','sql-watches']` (each hidden and redirected to Models while its member is absent), and add `keepPartners` and `keepSqlWatches`.
- `src/ocutalon/cls/OcuTalon/Test/Web/LeakScan.cls` -- NEW helper. `Check(case, needles, log, header, allowedGlobals)` holds the body of L260-282 of `OnCallSettingsApi`, which now calls it. The pins are unchanged.
- `src/ocutalon/cls/OcuTalon/Test/Core/SettingsPartners.cls` -- NEW, on the `SettingsOpsProbe` with real handoffs. It covers every partner row of the matrix:
  - `TestAddEditRemoveAudited`;
  - `TestRefusalsNameFieldsOnly`;
  - `TestNothingChanged`;
  - `TestProductionsMustBeCurrent`;
  - `TestOnlineDemo`;
  - `TestHandoffMissing`;
  - `TestForProductionOnlyStoredContacts` (another production's contact, and a contact in the same production class under another namespace, are excluded);
  - `TestValuesMember`;
  - `TestListProductionsVerb` (demo not_available);
  - `TestTextsOffOnDemo`;
  - `TestSqlBuiltReadsTheMessageMap`.
- `src/ocutalon/cls/OcuTalon/Test/Web/PartnerSettingsProbe.cls` and `PartnerSettingsApi.cls` -- NEW:
  - `TestMapAndRoute`;
  - `TestNonAdmin403`;
  - `TestOnlineDemoRefusesFirst`;
  - `TestBadBody`;
  - `TestSubmitFailsOrThrows`;
  - `TestCommandHoldsOnlyTheHandoff`;
  - `TestValuesOnlyInTheAuditLog`: real production; `LeakScan.Check` allows `OcuTalonP.PartnerContactD` only, with the audit entries as positive control.
- `src/ocutalon/cls/OcuTalon/Test/Web/SqlWatchSettingsProbe.cls` and `SqlWatchSettingsApi.cls` -- NEW, with the fixture `WatchOps` (the `Submit` seam records the command and answers a scripted `CommandResult`; `Built()` is scripted):
  - `TestNotBuiltIs501AndSubmitsNothing`;
  - `TestSaveSubmitsExactFields`;
  - `TestRefusalRelayedUnderQuery`;
  - `TestShapeRefusals`;
  - `TestRemoveOwnRowOnly`;
  - `TestNonAdmin403`;
  - `TestOnlineDemoRefusesFirst`;
  - `TestValuesListsOwnSqlRowsOnly` (fixture `BackgroundCheck` rows written by the test and removed after).
- `src/ocutalon/cls/OcuTalon/Test/Core/CommandsRouting.cls` -- `TestListProductionsRouting`: web_admin reaches SettingsOps; every other origin is not_allowed; it is no tool verb; and it has the bounded wait.
- `Test/Msg/Contracts.cls` -- add the verb rows.
- `Test/Core/SettingsSave.cls:441` -- `...,channels,on-call,partner-contacts`.
- Web unit tests:
  - `web/scripts/partner-view.test.mjs` and `sql-view.test.mjs` (NEW): the rules and every string verbatim;
  - `settings-view.test.mjs`: the section list;
  - `settings-refusal-sources.test.mjs`: `SAVING`;
  - `announce-focus-sources.test.mjs`: both new sections;
  - `ux-strings.test.mjs`: SOURCES;
  - a rail-view case in which a `sql_query` fixture check renders as a check row named by its display name.
- `web/e2e/settings/partner-contacts.spec.ts` -- NEW, serial, on the real stack, with `afterAll` removing the `zz` contacts:
  - P1: nav, heading, labels and keyboard;
  - P2: add, then check GET and the audit entries;
  - P3: a bad address plus no production marks both fields, focuses the address and changes nothing;
  - P4: edit, then remove.
- `web/e2e/settings/sql-watches.spec.ts` -- NEW. The `page.route` fixture adds `sql-watches` to GET and answers the POSTs:
  - Q1: labels and keyboard;
  - Q2: save shows the message and the row;
  - Q3: a refusal shows under Query;
  - Q4: remove;
  - Q5: with no member, the nav has no SQL link.
- `web/e2e/api/partner-contacts.spec.ts` -- NEW, real HTTP:
  - H1: LIVE `OcuTalonUser` gets 403 on GET and on both POSTs;
  - H2: an admin add gets 200, and `ForProduction` returns the contact in a fresh `irisScript`;
  - H3: a bad address gets 400 `["email"]`.
- `web/e2e/api/sql-watches.spec.ts` -- NEW, state-derived as 36.4's O1: when GET has no `sql-watches`, the POST is 501 `not_built`; when it has one, an admin's save and remove succeed.
- `web/e2e/settings/settings.spec.ts` and `on-call.spec.ts` -- `NAV_LINKS_ADMIN`/S1/S1f/O6 counts and lists gain "Partner contacts", and "SQL query watches" only when GET carries it.
- Spine (Rule 20, by the lead at the gate, once G1/G2 are ruled):
  - L770-772: the two body contracts;
  - L1560: the `ForProduction` shape and the audit setting names;
  - a `ListProductions` row next to L1631;
  - under G2-a, the `Fix.PartnerContacts` `TABLE` contract;
  - then `memlog.py append`, `lint_spine.py` and a refreshed `updated:`.

**Acceptance Criteria:**
- AC1. Given an admin on Partner contacts, when they add, edit or remove a contact, then `SettingsOps` writes or deletes its `PartnerContact` row, each changed field has its `Settings` audit entry (written before the row, in one transaction, with from, to, the admin and the session), and the page shows "Saved. Applies within a minute. Recorded in the audit log." with the list updated.
- AC2. (Integration: consumer `Data.PartnerContact.ForProduction`, the read path for 23.5's reader.) Given saved contacts, when a fresh process calls `ForProduction(namespace, production)`, then it returns exactly the stored contacts that name that pair, as `[{id, name, address}]` in ID order, and an edited-away or removed contact is gone at once.
- AC3. Given an invalid name, address or production list, when the admin saves, then each field shows its accepted error, focus moves to the first, and nothing is written or audited (UX-DR36).
- AC4. (DW-1254.) Given a saved partner change through the real production, when the leak scan runs, then the name and the address appear in the IRIS audit entries and in `OcuTalonP.PartnerContactD`, and in no message body, `Ens.MessageHeader`, event-log row, trace global or other `^OcuTalon*` global. `SaveSettings.Changes` is exactly `{handoff}`.
- AC5. (Fixture `WatchOps`.) Given the SQL section is built, when an admin saves a query, then exactly one `SaveSqlWatch` {save, "", name, query, minutes} with origin web_admin is submitted, the owner's Message shows, and a refusal shows the owner's plain reason under Query with nothing else submitted.
- AC6. Given `sql_query` rows of the admin's session, when Settings loads, then they are listed with Schedule, Last run and Last result. Rows of other sessions or other kinds are absent, and the rail renders a `sql_query` check as a check row (rail-view fixture).
- AC7. Given a saved query, when the admin removes it, then exactly one `SaveSqlWatch` {remove, ref} is submitted and the row leaves the list from the answer. A ref that isn't the caller's own `sql_query` row is 404, and nothing is submitted.
- AC8. Given `WatchOps` does not handle `SaveSqlWatch` (feature today), when Settings loads or the route is called, then there is no `sql-watches` member and no SQL section, and the POST is 501 `not_built` with "This part of OcuTalon isn't built yet. Nothing was changed." and nothing submitted.
- AC9. Given a non-admin, when they call either route, then both are 403 `not_admin`. Given the online demo, when an admin calls either route or loads Settings, then both routes are 409 `not_available` with their accepted texts before the body is read, GET has neither member, `ListProductions` is `not_available`, and nothing is written.
- AC10. Given the Playwright specs, when both sections are used by keyboard alone, then every control is labelled, a Remove names its object, and the stored contacts and the submitted fields match (NFR-25, UX-DR130).
- AC11. Given `Fix.PartnerContacts` has no `TABLE` parameter (today), when Partner contacts shows, then the section shows no `partnersHelp` and Remove has no confirm. Given a probe value of 1, when it shows, then `partnersHelp` shows and Remove asks `partnerRemoveConfirm`.

## Spec Change Log

## Review Triage Log

## Design Notes

### 23.8 finding (for the gate)

- **The SQL section today.** On feature, the section's save would submit `SaveSqlWatch`, and `CommandsIn` routes it to `WatchOps` (L379). `WatchOps`' `MessageMap` (L83) maps only `StartWatch` and `StopWatch`.
  - An unmapped request reaches `Ens.BusinessOperation.OnMessage`, which answers `$$$EnsError($$$EnsErrRequestNotHandled)` (`irislib/Ens/BusinessOperation.cls:707-710`). That status is not code 5003, so `CommandsIn.IsStub` is false.
  - The submit therefore answers `Ok 0`, `failed`, "Something went wrong inside OcuTalon, so the command may not have finished.", plus one error in WatchOps' event log. Nothing is written.
  - A page that relays it would show "Couldn't save. Nothing was changed." (500).
  - Spine L1222 records the same as an inference. Task 0 measures it.
- **Removal.** Story 36.2 made no separate remove verb. A removal is the same `SaveSqlWatch` with `Action` `remove`, and it meets the same `failed` today.

### Gate questions (Planner; not decided here)

**G1. The 23.8 dependency of the SQL half.**
- **(A) [recommended]** Build both sections now.
  - The SQL section is gated on the code itself (`SqlBuilt()`: `WatchOps`' compiled MessageMap names the verb). Until 23.8 merges it is hidden, and its route answers the approved not-built text. After 23.8 merges it appears with no further change.
  - Tests use a fixture `WatchOps`, as the AC says. 24.2 merges independently of 23.8.
  - Residual: the end-to-end save, row and rail are proven by 23.8's own tests and by the state-derived api spec. 23.8 must handle the verb through `MessageMap`; this goes to 23.8 as a DW bullet.
- **(B)** Split: 24.2 keeps partner contacts, and a new 24.5 takes SQL watches with `story_waits` on 23.8. This changes a dependency statement and inserts a story (owner category 5).
- **(C)** Keep 24.2 whole, with a `story_waits` on 23.8. 24.2 then merges only after Lane A's 23.8, which is in backlog.

**G2. 23.5's reader, which is Lane A's.**
- The AC's "only addresses a partner warning can be sent to", and the condition on `settings.partnersHelp`, need 23.5's `Fix.PartnerContacts.For` and `Named` to read the table. That is a Lane A file (AD-29).
- DW-1254's extension (Planner, 2026-11-13, item 6) also requires `ProposeFix`, `DryRun`, `DryRunResult` and `PartnerNotice` to carry contact ids, not addresses, "once 24.2 makes contacts real". All of that is Lane A code: `IncidentManager`, `Fix.Kind.PartnerWarning` and `Fix.Msg.*`. Epic 23 is in progress, so these files are contended.
- **(a) [recommended]** 24.2 builds the table, the writer, `ForProduction` (the same shape as `For`, so the switch is small), the section and the leak scan.
  - A Lane A story, which the gate names (suggested: a new Story 23.10, "Partner warnings use the listed contacts, by id"), switches `For` and `Named` to `ForProduction(incident.Namespace, ...)`. It also decides whether the demo-mode fixture stays as a simulated fallback, applies DW-1254's id extension, adds `Parameter TABLE = 1` to `Fix.PartnerContacts`, and pins both halves of `partnersHelp`.
  - Moving those AC parts is a veto item (7/8).
  - Until the switch lands, the page shows the section without `partnersHelp`, with the proposed not-yet line (or nothing, if that line is refused), and with no Remove confirm, whose text would claim that warnings go there.
- **(b)** A lane exception lets 24.2 edit those Lane A files itself. Not recommended: the files are contended with Epic 23, and the story roughly doubles in size.

### Decided in-stage

1. The two routes are forwarded Maps, as 36.4's were, and Api's `TestRoutes` still counts 38.
2. The partner saver works on one contact per save (save or remove), which matches the per-contact Add, Save and Remove of the UX texts.
3. Each changed field gets its own audit entry, as each on-call key does.
4. Productions come through the new read verb `ListProductions`, because `Reader.Productions()` needs the production job. AD-13's amendment sends reads beyond the caller's own rows through a verb. Production names are not personal data, so its `Data` is inline, as `ListMcpServers`' is. This verb is a veto item.
5. The contact list is read in the web process only through `PartnerContact.List()`, the owning class's method (AD-13, L484). The `web-global-reads` baseline is unchanged.
6. The SQL section has no edit: 23.8 has not named its query column. Remove acts at once, as an MCP source's does.
7. A WatchOps refusal is relayed under Query: every refusal 23.8's AC names is about the statement, and no outcome-to-field contract is assumed.
8. The SQL route checks the minutes as a whole number from 1 to 1440 and reuses `settings.onCallBadMinutes`. A tighter bound from 23.8 comes back as its own message.
9. Nav order: On call, then Partner contacts, then SQL query watches.
10. The SQL query text stays in the traced `SaveSqlWatch`. That is Story 36.2's ruled contract, noted here for the Planner because an admin's query may hold literal values.

### Governing ADs (Rule 6)

- AD-1: commands, `SaveSqlWatch` and `ListProductions`.
- AD-3: the private global from `short-names.tsv`.
- AD-4: SQL rows belong to the session, and only own rows are listed or removed.
- AD-13: admin routes; web reads go only through the owning class.
- AD-17: `Bridge.Audit` is the only writer.
- AD-18: `sql_query` rows are 23.8's.
- AD-19: step-5 sections, `SecretHandoff`, V3 audit.
- AD-24: personal data stays out of the trace.
- AD-25: the online demo.
- AD-29: lanes; no Lane A edit.
- AD-33: one writer per table.

### Integration ACs, Consumed-by, Consumes (Rules 1, 2)

- **Integration ACs:** AC2 (`ForProduction` in a fresh process, as a consumer reads it) and AC5/AC7 (the route against the fixture owner).
- **Consumed-by:**
  - the Lane A switch story named under G2 (`ForProduction`, and `TABLE`);
  - 23.8 (`SaveSqlWatch` from this page);
  - 24.4 (a partner warning's recipients, through 23.5's fixture until the switch).
- **Consumes:** `SecretHandoff`, `Bridge.Audit.Record`, `Watch.Reader.Productions` (through the verb), `Ownership.Checks`, `CommandsIn` and `SaveSqlWatch` (36.2), and 36.4's `Web.OnCallSettings` and `SaveOnCall` prologue.

### Extend, don't copy (Rule 2)

- `Web.PartnerSettings` extends `Web.OnCallSettings`, whose `OffText` becomes overridable.
- `SavePartner` shares `HandoffBody`, extracted from `SaveOnCall`.
- `SqlWatchRows` uses `CheckRows`, generalized from `SourceRows`.
- `ProductionsRoster` mirrors `OnCallRoster`, which is a copy. The reason: one answer comes inline and the other through a handoff.
- `WritePartner` copies `SaveProduct`'s transaction, because it writes rows, not `Apply` keys.
- `Web.SqlWatchSettings` copies `McpSettings.SetSource`'s shape for a different command and different fields.
- `LeakScan.Check` is lifted from 36.4's test, which now calls it.
- `ListProductions` copies `ListOnCallUsers`.

### Ledger (Rule 17)

The slice for `24-2-set-partner-contacts-and-saved-sql-query-watches-in-settings` holds DW-1254.
- **Addressed:** the handoff, `Changes` exactly `{handoff}`, values in the audit entry only, and the leak scan (AC4).
- **Residual under G2-a:** the extension (ids, not addresses, in Lane A's partner messages). It is re-owned with the reader switch to the Lane A story the gate names, so DW-1254 is not fully `resolved-by` 24.2.

### Size and split

The story is oversized and has two goals. If the gate prefers to split it, the line is G1-B: partner contacts (table, writer, verb, section, leak scan) form one story, and SQL watches (route, section, `SqlBuilt` gate, SQL tests) the other.

## Public text

Every new user-facing string, for the Planner. The accepted texts of EXPERIENCE.md › "Settings (step 5)" are reused verbatim and are not repeated here.

- **NEW** (G2-a only) `settings.partnersNotYet`, "OcuTalon doesn't send partner warnings to these contacts yet. It keeps them for when it does."
  - Where: Settings > Partner contacts, under the heading in place of `settings.partnersHelp`, while `Fix.PartnerContacts` has no `TABLE` parameter.
  - On the online demo it never shows, because the section is absent.
  - If refused, the section shows no help line.
- **REUSED in a new place:** `settings.onCallBadMinutes`, "Enter a whole number of minutes from 1 to 1440. Nothing was changed.", as the SQL interval field error. Online demo: absent.
- **REUSED in a new place:** "Check every", as the SQL interval label. Also reused: the rail's duration, result and `when` texts in the SQL list's cells, "Cancel" (`MCP_TEXTS.cancel`) in the partner Remove confirm, "Saved. Applies within a minute. Recorded in the audit log.", "Couldn't save. Nothing was changed." and "This part of OcuTalon isn't built yet. Nothing was changed." (the SQL route's 501).
- **Not 24.2's:** the SQL result messages are `WatchOps`' (23.8) and are shown verbatim.
- **Conditions of accepted texts:**
  - `settings.partnersHelp` ships only once the switch lands (G2).
  - `settings.partnerRemoveConfirm` shows only while warnings use the table.
  - `settings.sqlHelp` shows only while the SQL section is built.

## Veto items

**NEW**
1. **The command verb `OcuTalon.Msg.Command.ListProductions`.** It is a read with no property, from web_admin only, owned by `SettingsOps`, and no tool verb. It has the 20 s bounded wait (`busy`). Its result is Ok 1 `listed` with `Data {"productions":[{namespace,production,displayName}]}` inline. It carries no SessionRef and is not counted by the evaluation or the allowance. Online demo: `not_available`, and it is unreachable anyway (admin only).
2. **(G2-a only) The cross-lane contract `OcuTalon.Fix.PartnerContacts` `Parameter TABLE = 1`.** Lane A adds it when its reader uses the table; 24.2 only reads it.
3. **The audit setting names `partnerContact.<Ref>.name`, `.email` and `.productions`.** They hold the from and to values (partner names and addresses) in the IRIS audit log only, under V3 and AD-17's V4 allowance. Online demo: never written.
4. **The two body contracts and the `ForProduction` return shape** (Rule 20 spine bullets): `[{id = row ID, name, address}]`.

**Already ruled (no new decision):**
- the `PartnerContact` table, its global, its columns and no purge (36.2 V1-V7);
- the routes `POST /api/v1/settings/partner-contacts` and `/sql-watches`;
- `SaveSqlWatch` from web_admin only;
- `SecretHandoff` carrying contact data (S1/S2, DW-1254);
- values in the IRIS audit entry (V3).

There is no new role, grant, resource, retention rule, outward action, web dependency or online-demo capability: a visitor can set neither contacts nor SQL watches (403, then 409).

## Verification

`LD="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-d"`. Every IRIS call sets `OCUTALON_LOCK_DIR="$LD" OCUTALON_TEST_WEB_PORT=52804 OCUTALON_LOCK_OWNER='epic=24 stage=implement'`. The warm tag is `e24s2iw`, the fresh tag `e24s2i`. Each line is one foreground call of at most about 150 s (`timeout: 600000`). One test class per call, never two test calls in one message.

**Shared surfaces:**
- the Settings section list and its nav count, which is now state-derived for SQL;
- the GET `/v1/settings` `sections` keys (`SettingsSave:441`);
- the `CommandsIn` Routes table and the verb lists in `CommandsRouting` and `Contracts`;
- `short-names.tsv`;
- the `ux-strings`, `settings-refusal-sources` and `announce-focus-sources` lists;
- `settings.spec.ts` S1/S1f and `on-call.spec.ts` O6's link counts.

Standing criterion: every test added or changed passes on a fresh environment, in either order.

**Commands:**
- (once) `npm --prefix web ci` -- installs `web/node_modules`, which is absent in this worktree.
- (once) `... OCUTALON_RUN_TAG=e24s2iw ci/warm.sh up` -- ready.
- (loop) `... OCUTALON_WARM=1 OCUTALON_RUN_TAG=e24s2iw ci/iris.sh class <C>` for each of `OcuTalon.Test.Core.SettingsPartners`, `Test.Web.PartnerSettingsApi`, `Test.Web.SqlWatchSettingsApi`, `Test.Web.OnCallSettingsApi`, `Test.Core.SettingsOnCall`, `Test.Core.CommandsRouting`, `Test.Msg.Contracts` and `Test.Core.SettingsSave` -- each prints `CLASS … passed`. After a `SettingsOps` change, restart the item as 36.4's notes say.
- (once) `... OCUTALON_RUN_TAG=e24s2iw ci/warm.sh down`.
- (once) `... OCUTALON_RUN_TAG=e24s2i ci/iris.sh class OcuTalon.Test.Web.PartnerSettingsApi` -- passes on a fresh stack (the leak scan in the real production).
- (loop) `npm --prefix web test`, then (once) `npm --prefix web run lint` and `npm --prefix web run build` -- each passes with no budget error.
- (once) `... OCUTALON_RUN_TAG=e24s2i ci/iris.sh build`, then one call each of `ci/iris.sh live sign-in-2 --part k/N`, for the part holding only `partner-contacts.spec.ts`, then `sql-watches.spec.ts`, then `settings.spec.ts` with `on-call.spec.ts`. Then `live sign-in --part k/N` for `api/partner-contacts.spec.ts`, then `api/sql-watches.spec.ts`. Find k/N with `npm --silent --prefix web run e2e:sign-in-2 -- --list --reporter=json` (or `e2e`) and `node web/scripts/e2e-part.mjs`, choosing N so that the part ends inside about 150 s -- all pass.
- (once) `bash docker/tests/test-class-rules.sh`, `test-ci-config.sh` and `test-boundaries.sh` -- pass. Then `... ci/iris.sh live storage-roundtrip` -- passes (the new storage blocks).
- (once) `... OCUTALON_RUN_TAG=e24s2i ci/iris.sh teardown`.
- Fresh-environment check (the lead): `ci/iris.sh shard lane-b --part k/n` and `--reverse`, for the parts holding the added classes, each inside about 150 s.

**Mutations (Rule 19; record each as `mutation: … → …`):**
- AC1: skip `WriteAudit` → `TestAddEditRemoveAudited` red.
- AC2: drop the namespace match in `ForProduction` → `TestForProductionOnlyStoredContacts` red.
- AC3: accept `productions` [] → `TestRefusalsNameFieldsOnly` red.
- AC4: put the body in `Changes` → `PartnerSettingsApi.TestValuesOnlyInTheAuditLog` red.
- AC5: send `Action` "" → `TestSaveSubmitsExactFields` red.
- AC6: drop the Kind filter in `CheckRows` → `TestValuesListsOwnSqlRowsOnly` red.
- AC7: skip the own-row check → `TestRemoveOwnRowOnly` red.
- AC8: `SqlBuilt` returns 1 → `TestNotBuiltIs501AndSubmitsNothing` red.
- AC9: move the demo check after the body read → `TestOnlineDemoRefusesFirst` red.
- AC10: remove the Name label → `partner-contacts.spec.ts` P1 red.
- AC11: ignore `warningsUseThese` → the `partner-view.test.mjs` help case red.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none. Planning halted after the ready-for-development gate, as the invocation directed. The plan follows the recommended options for gate questions G1 and G2 (Design Notes). It also needs the gate to rule on the NEW items under `## Public text` (`settings.partnersNotYet`) and `## Veto items` (the `ListProductions` verb, the `Fix.PartnerContacts` `TABLE` contract, the audit setting names, and the body and return contracts) before implementation.
