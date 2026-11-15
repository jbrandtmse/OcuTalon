---
title: 'Story 24.2: Set partner contacts and saved SQL query watches in Settings'
type: 'feature'
created: '2026-11-15'
status: 'done'
baseline_revision: '836f45ab07c5cc3658226113e5fed6c315513425'
review_loop_iteration: 0
followup_review_recommended: true
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-24-context.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-36-4-set-the-on-call-person-and-backup-in-settings.md'
warnings: ['oversized']
deferred:
  - summary: >-
      No test makes the row write fail after the audit write succeeds, so the rollback of the audit entry in WritePartner is not pinned.
    evidence: |-
      TestAddEditRemoveAudited fails the audit write only; SettingsPartners runs on the probe, whose audit record is outside the transaction, and the real Bridge.Audit is reached only by PartnerSettingsApi, where the productions come from the real roster and cannot exceed the 4000-character MAXLEN that would make %Save fail. Removing the TROLLBACK in the second error block keeps every test green.
    location: >-
      src/ocutalon/cls/OcuTalon/Core/SettingsOps.cls:WritePartner
    severity: medium

---

<intent-contract>

## Intent

**Problem:** Story 36.2 named the partner-contact table and the `partner-contacts` settings section, but nothing writes or reads them. Lane A's Story 23.13 can only switch partner warnings to admin-chosen contacts once the table, its writer and its reader exist.

**Approach:**
- Add `OcuTalon.Data.PartnerContact`, its only writer (a `contacts` saver in `SettingsOps`) and its reader `ForProduction`. Contact values reach the saver only through `SecretHandoff`, as 36.4's on-call body does (DW-1254).
- Add the admin-only route `Web.PartnerSettings`, the read verb `ListProductions`, and the Settings section.
- The section is shown only while `OcuTalon.Fix.PartnerContacts` has `Parameter TABLE = 1`. Lane A's 23.13 sets it; 24.2 only reads it. Until then the section is hidden, with no "not yet" text.

## Boundaries & Constraints

**Always:**
- `SettingsOps` is the only writer of `PartnerContact`. It validates the whole body before writing anything.
- Audit: one `Settings` entry per add, edit or removal, through `Bridge.Audit.Record`, written before the row in one transaction that a failure rolls back. Its setting is `partnerContact.<Ref>`; its from and to name WHICH fields changed (`name`, `email`, `productions`), never a value. The admin's IRIS user, the session Ref and channel `web` are recorded.
- Partner values travel only through `SecretHandoff`. The route offers the body before the submit and discards it on every path. `SaveSettings.Changes` is exactly `{"handoff":"secret://handoff/<name>"}`. A refusal names fields only.
- A contact's name and address are stored only in its `PartnerContact` row. No command, `CommandResult`, log line, trace, notice or audit entry holds them, so removing the row removes them.
- The section's visibility reads `TABLE` alone: shown when it is 1, hidden otherwise (absent, 0 or anything else). The route and the saver do not read it.
- `ListProductions` is read-only, `web_admin` only, carried out by `SettingsOps` with the 20 s bounded wait, `not_available` on the online demo, and no tool verb: a `tool` origin, or any origin inside a bridge context, is refused.
- Admin only: 403 `not_admin` (Api `OnPreDispatch` and the route). Online demo: the route answers 409 `not_available` (`settings.partnersOffOnDemo`) before reading the body, `SettingsOps` also answers `not_available`, nothing is written, and `GET /v1/settings` has no `partner-contacts` member.
- Ship only the accepted texts of EXPERIENCE.md › Settings (step 5), verbatim.
- Every IRIS test runs on a lane-D throwaway (`ci/iris.sh`, `ci/warm.sh`), never on a slot, and creates and removes its own contacts and sessions.

**Never:**
- No SQL query watch: no `sql-watches` section, route, `Web.SqlWatchSettings`, `SaveSqlWatch` submit or SQL text. That is Story 24.5's.
- Do not edit Lane A files (`Fix/**` including `Fix/PartnerContacts.cls`, `Watch/**`, `Watch/IncidentManager.cls`, `Data/BackgroundCheck.cls`, `Msg/Catalog/*.cls`), and do not switch 23.5's reader. Both are 23.13's.
- No "not yet" text (`settings.partnersNotYet` is refused), and no section that switches itself on at runtime.
- No change to `Core/SecretHandoff.cls`, `README.md`, `GUIDE.md`, the More to try registry, `ci/units.sh`, `.github/workflows` or `release/**`. No role, grant, resource or new Web application. Never widen `OcuTalonUser`.
- Do not send any email or notice. Do not put a partner value into a `$$$LOG*` text or a status text.

## I/O & Edge-Case Matrix

The body is `{action, ref, name, email, productions}`: `action` is `save` or `remove`; `ref` is "" for a new contact; `productions` is `[{namespace, production}]`, each an entry of `Watch.Reader.Productions()` read in the production job when the save runs. A remove is `{action, ref}` only.

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Add | save, ref "", name 1-128 chars after trimming, an address `SettingsOps.IsAddress` accepts (≤254), one or more productions | Row inserted (`CreatedAt`/`UpdatedAt` UTC); one audit entry, from "" to `name,email,productions`; 200 with sections | none |
| Edit | save, an existing ref, some fields changed | Row updated, `UpdatedAt` set; one audit entry naming only the changed fields on both sides | none |
| Nothing changed | save with the stored values | 200 done; no audit entry; row untouched | none |
| Remove | remove, an existing ref | Row deleted; one audit entry, from `name,email,productions` to "" | none |
| Bad fields | name "" or >128 or with `@{` or a control char; bad address; `productions` [] or with an entry that is not current or is repeated | 400 `bad_settings` naming `name`/`email`/`productions`; nothing written or audited | page: `partnerBadName`, `badEmail`, `partnerNoProduction` under each field; focus on the first |
| Shape | missing or extra member, wrong type, unknown action, unknown ref, body not an object | 400 `bad_settings` with `[]` | page: "Couldn't save. Nothing was changed." |
| TABLE 0 (feature today) | `Fix.PartnerContacts` has no `TABLE`, or not 1 | GET has no `partner-contacts`; the page lists and opens no Partner contacts section (address falls back to Models) | none |
| TABLE 1 | `TABLE = 1` (23.13; a probe here) | GET has `partner-contacts` = `{contacts, productions}`; the section shows its heading and `partnersHelp` | none |
| ListProductions | web_admin; any other origin; inside a bridge context; online demo | Ok 1 `listed`, `Data {"productions":[{namespace,production,displayName}]}`; `not_allowed`, nothing sent; `not_allowed`; `not_available` | no answer in 20 s: `busy`, roster [] |
| Non-admin / demo | `OcuTalonUser`; `onlineDemo` 1 | 403 `not_admin`; 409 `not_available` with `partnersOffOnDemo`, body unread | as Always |
| Server failure | submit error, a throw, `failed`, `not_audited` | 500; handoff discarded; row unchanged | "Couldn't save. Nothing was changed." |

</intent-contract>

## Code Map

- `src/ocutalon/cls/OcuTalon/Core/SettingsOps.cls` -- the writer.
  - `Carry` L197 (verb branches; `ListOnCallUsers` L207 is the line to mirror).
  - `AuditData` L250 (`{setting, from, to, irisUser, sessionRef, channel}`), `WriteAudit` L271 (probe seam).
  - `HeartbeatAuditForm` L458 and `AuditForm` L754: precedents for an audit "form" that is not the value.
  - `XData Sections` L906-946: the `on-call` row ends it; append `{"slug":"partner-contacts","kind":"contacts","fields":[]}`.
  - `Values` L971: the kind skip L976; the on-call line L995 is the pattern for the new member.
  - `Save` L1039: the `oncall` dispatch L1049. `Refused` L1074.
  - `SaveProduct` L1128: the audit-then-write transaction to mirror. It cannot be reused, because it writes `Setting` keys through `Apply`.
  - `IsAddress` L1929, `HasControl` L1947, `TakeSecret` L2362 (`HANDOFFWAIT` 2 s).
  - `SaveOnCall` L2538: its handoff prologue (demo discard, exactly `{handoff}`, take, parse) becomes the shared helper.
  - `ListOnCallUsers` L2710, `OnCallRoster`/`SubmitRoster` L2731-2763: the read-verb pattern. `OnCallValues` L2768 uses `%Dictionary.CompiledClass` as a compile-time gate (`pagesBuilt`), the precedent for reading `TABLE`.
- `src/ocutalon/cls/OcuTalon/Web/OnCallSettings.cls` (87 lines) -- the parent of `Web.PartnerSettings`: `Refusal` L29 and `Hand` L52 use `MESSAGEONCALLOFF` literally; `Save` L37 sets `Slug` "on-call"; `Offer` L77 and `Submit` L83 are seams.
- `src/ocutalon/cls/OcuTalon/Web/Api.cls` -- Maps L313-316 (add one after on-call); class comment L121-126; `MESSAGENOTADMIN` L204; `IsSettingsUrl` L425 already covers the path.
- `src/ocutalon/cls/OcuTalon/Core/CommandsIn.cls` -- `TOOLVERBS` L65, the origin gate L114-117 (a bridge context makes the origin `tool`), `Send` L198 bounded wait (`SendSearch`, `SEARCHTIMEOUT` L75 = 20), the class-comment bullet L21 for `ListOnCallUsers`, and the `Routes` table.
- `src/ocutalon/cls/OcuTalon/Msg/Command/ListOnCallUsers.cls` -- the sibling of NEW `ListProductions`.
- `src/ocutalon/cls/OcuTalon/Watch/Reader.cls:113` `Productions()` -- `[{namespace, production, displayName}]`; it reads the `ServiceUser` setting, so it runs in the production job and throws when it cannot. Read only (Lane A).
- `src/ocutalon/cls/OcuTalon/Fix/PartnerContacts.cls` -- Lane A's demo fixture; `For(production)` L21 returns `[{id, name, address}]`, the shape `ForProduction` returns. It has no `TABLE` parameter today. Read only.
- `src/ocutalon/cls/OcuTalon/Data/Webhook.cls` -- the sibling for `Data.PartnerContact`: Lane B, `DEFAULTGLOBAL` from `src/short-names.tsv` (row L37), object access only.
- `src/bridge/cls/OcuTalon/Bridge/Audit.cls` -- `SHAPESETTINGS` L31 `setting,from,to`; `Record` L91; the description is "Setting <setting> changed" L179.
- Web:
  - `web/src/app/settings/settings-view.ts`: `SETTINGS_TEXTS.sections` L44 and the `onCall` block L95 (its `badEmail` is reused); `SETTINGS_SECTIONS` L159 (the new slug goes after `on-call`; the "ten sections" comment becomes eleven).
  - `settings-page.ts`: on-call imports L20, `@case` L70, the hide-when-absent rule L253-260 (`onCall`, `sections`, `active`), `keepOnCall` L350.
  - `on-call-section.ts` and `on-call-view.ts`: the form, field-error, focus and announce pattern. `mcp-section.ts`: the confirm dialog L848-875 (`MCP_TEXTS.cancel`, `SETTINGS_TEXTS.failed`).
  - `api/api-client.ts:66` `saveSettings`; `api/api-types.ts` `SettingsSections`.
- Tests to extend:
  - `Test/Core/SettingsOpsProbe.cls` (shared probe: `SubmitRoster` L44, `WriteAudit` L70) and `Test/Core/SettingsOnCall.cls` (the handoff pattern).
  - `Test/Core/SettingsSave.cls:441`: the expected section keys.
  - `Test/Web/OnCallSettingsApi.cls` L240-283 `TestValuesOnlyInTheAuditLog` (the leak scan: `Test.Bridge.AuditLog` `Now`/`Wait`, `Test.Web.WebhookTools` `LastLog`/`LastHeader`/`LogText`, `Test.Core.SecretHandoff` `Leaks`/`TraceLeaks`, `TableHolds` L419) and `Test/Web/OnCallSettingsProbe.cls`.
  - `Test/Core/CommandsRouting.cls` `TestListOnCallUsersRouting` L189 (origins, `TOOLVERBS`, `CommandsTimeoutProbe`) and `TestContextMeansTool` (a bridge context); `Test/Msg/Contracts.cls` L42 and L391.
  - `web/e2e/settings/settings.spec.ts` (S1 `NAV_LINKS_ADMIN`) and `on-call.spec.ts` (O6's link count), `web/e2e/api/on-call.spec.ts` (real HTTP; `irisScript` from `web/e2e/support/iris.ts:108`), `web/scripts/settings-view.test.mjs`, `settings-refusal-sources.test.mjs`, `announce-focus-sources.test.mjs`, `ux-strings.test.mjs`.
- Playwright projects: `web/e2e/settings/**` runs in `sign-in-2` (`web/playwright.config.ts:52`, `ci/iris.sh live sign-in-2`); `web/e2e/api/**` in `chromium` (`live sign-in`).
- Spine `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md`: L767 (V3, from/to values in the IRIS audit log), L770-772 (the step-5 sections), L1560 (the PartnerContact table), L1631 (the `ListOnCallUsers` row), L484 (AD-13).

## Tasks & Acceptance

**Execution:**
- Task 0 (measure on a lane-D throwaway; record under Verification): `irisScript` can run `##class(OcuTalon.Core.SettingsOps).PartnerValues()` in a fresh process and gets at least one production (the Playwright fixture depends on it); and `$Parameter("OcuTalon.Fix.PartnerContacts","TABLE")` reads "" on feature.
- `src/short-names.tsv` -- append `PartnerContact	^OcuTalonP.PartnerContact	OcuTalon.Data.PartnerContact	B`.
- `src/ocutalon/cls/OcuTalon/Data/PartnerContact.cls` -- NEW `%Persistent`, committed `Storage Default`, object access only, the class description naming `SettingsOps` as the only writer.
  - Columns: `Ref` (22, unique index), `Name` (128), `Email` (254), `Productions` (JSON text, MAXLEN 4000), `CreatedAt`, `UpdatedAt` (20). No index on `Name` or `Email`.
  - `ForProduction(namespace, production)` → `[{id, name, address}]`, `id` the row ID, in ID order; a contact matches only when one entry matches both values.
  - `List()` → `[{ref, name, email, productions}]` by upper-cased name, then Ref. `RefOpen(ref)`.
- `src/ocutalon/cls/OcuTalon/Msg/Command/ListProductions.cls` -- NEW, the shape of `ListOnCallUsers` (no property); the description says read verb, web_admin only, no tool verb.
- `src/ocutalon/cls/OcuTalon/Core/CommandsIn.cls` -- route `{"verb":"ListProductions","owner":"SettingsOps","origins":"web_admin"}`; `Send` gives it the bounded wait; one class-comment bullet and one `Routes` comment line. Not in `TOOLVERBS`.
- `src/ocutalon/cls/OcuTalon/Core/SettingsOps.cls`:
  - `Carry`: `ListProductions` → `ListProductions()`: `not_available` on the demo; else Ok 1 `listed` with `Data {"productions":[...]}` inline; `failed` when `Reader.Productions()` throws.
  - `Sections`: the `partner-contacts` row. `Values`: skip kind `contacts` at L976; off the demo and when `PartnersShown()`, add `partner-contacts` = `PartnerValues()` = `{contacts: PartnerContact.List(), productions: ProductionsRoster()}`. `ProductionsRoster` mirrors `OnCallRoster` through a `SubmitProductions` seam and answers [] on any failure.
  - `PartnersShown(class As %String = "OcuTalon.Fix.PartnerContacts")`: 1 only when `$Parameter(class, "TABLE")` is exactly 1. Never throws.
  - `Save`: kind `contacts` → `SavePartner(command, changes)`.
  - Extract `HandoffBody(changes, offText, .body)` from `SaveOnCall`'s prologue; both savers call it, and `SaveOnCall` behaves as before.
  - `SavePartner`: the prologue, `PartnerProblems(body, .row, .odd)` (field names only, the matrix's rules, productions checked against `Reader.Productions()`), then `WritePartner`: one audit entry with `PartnerAuditForm`, then insert, update or delete, in one `TSTART`, with rollback, `not_audited` and `failed` as `SaveProduct` does.
  - `PartnerAuditForm(changed, side)`: the changed field names that hold a value on that side, comma-joined in the order name, email, productions (Design Notes).
  - `MESSAGEPARTNERSOFF` (`settings.partnersOffOnDemo` verbatim) and one class-description paragraph.
- `src/ocutalon/cls/OcuTalon/Web/OnCallSettings.cls` -- add overridable `Slug()` ("on-call") and `OffText()` (`MESSAGEONCALLOFF`), used in `Save`, `Refusal` and `Hand` instead of the literals. Behaviour unchanged.
- `src/ocutalon/cls/OcuTalon/Web/PartnerSettings.cls` -- NEW, extends `Web.OnCallSettings` with its own `UrlMap` (`<Route Url="" Method="POST" Call="Save"/>`), `Slug` "partner-contacts" and `OffText` `MESSAGEPARTNERSOFF`; the class description states the body contract.
- `src/ocutalon/cls/OcuTalon/Web/Api.cls` -- Map `/v1/settings/partner-contacts` → `Web.PartnerSettings`, and one class-comment bullet.
- Web:
  - `api/api-types.ts`: `PartnerContactsValues {contacts, productions}`, the body type, the optional `'partner-contacts'` member of `SettingsSections`. `api-client.ts`: `savePartnerContact` (POST).
  - `settings-view.ts`: `sections.partners` and a `partners` block of the accepted texts; the slug in `SETTINGS_SECTIONS` after `on-call`; the header comment.
  - `partner-view.ts` -- NEW, framework-free: `PARTNER_FIELDS`, `partnerBody`, `isPartnerDirty`, `productionKey`.
  - `partner-contacts-section.ts` -- NEW, built like `on-call-section.ts`: heading, `partnersHelp`, one form per contact (Name, Email address, a "Productions it concerns" fieldset of checkboxes labelled by `displayName`, Save changes, Remove), an Add contact form, and the Remove confirm (`partnerRemoveConfirm`, `MCP_TEXTS.cancel`). 400: mark the fields, focus the first. 403 denied, 409 the off text, else failed. Row controls take accessible names from their label plus the row's name cell (`aria-labelledby`), with no new string.
  - `settings-page.ts`: import and `@case`; generalize the on-call hide rule to `on-call` and `partner-contacts` (each hidden and redirected to Models while its member is absent); `keepPartners`.
- IRIS tests:
  - `Test/Core/SettingsOpsProbe.cls` -- add `SubmitProductions` (scripted answer) and `PartnersShown` (the real answer unless `^OcuTalonTest("SettingsOpsProbe","table")` is set; the test kills it).
  - `Test/Core/SettingsPartners.cls` -- NEW, on the probe with real handoffs; declares `Parameter TABLE = 1` for the 1 case: `TestAddEditRemoveAudited`, `TestRefusalsNameFieldsOnly`, `TestNothingChanged`, `TestProductionsMustBeCurrent`, `TestOnlineDemo`, `TestHandoffMissing`, `TestForProductionOnlyStoredContacts` (another production, and the same production under another namespace, are excluded; an edited-away or removed contact is gone at once), `TestTableStates` (`PartnersShown` is 1 for this class, 0 for `Test.Web.PartnerSettingsProbe`, which declares `Parameter TABLE = 0`, and 0 for `Test.Core.SettingsOnCall`, which has none; the real `Values()` has the member exactly when `PartnersShown()` is 1, so it holds before and after 23.13), `TestSectionShownAtTableOne` (probe flag 1: the member with contacts and productions), `TestListProductionsVerb` (shape; demo `not_available`).
  - `Test/Web/PartnerSettingsProbe.cls` and `PartnerSettingsApi.cls` -- NEW: `TestMapAndRoute`, `TestNonAdmin403`, `TestOnlineDemoRefusesFirst`, `TestBadBody`, `TestSubmitFailsOrThrows`, `TestCommandHoldsOnlyTheHandoff`, `TestValuesOnlyInTheRow` (real production; the scan of 36.4's test plus the audit rows: the entry exists with setting `partnerContact.<Ref>` and the field-name forms, and no audit row since the mark holds the name or the address; `Leaks` finds them only in `OcuTalonP.PartnerContactD`, as positive control; after a remove, nowhere).
  - `Test/Core/CommandsRouting.cls` -- `TestListProductionsRouting`: web_admin reaches SettingsOps only; every other origin is `not_allowed` with the oracle texts; a bridge context with origin web_admin is refused as `tool`; not in `TOOLVERBS`; the 20 s wait gives `busy`.
  - `Test/Msg/Contracts.cls` -- the verb in L42's list and a contract block beside L391.
  - `Test/Core/SettingsSave.cls:441` -- expected keys end `on-call`, plus `,partner-contacts` exactly when `SettingsOps.PartnersShown()` is 1.
  - `Test/Web/OnCallSettingsApi.cls` and `Test/Core/SettingsOnCall.cls` -- re-run unchanged (the `OffText`/`Slug` and `HandoffBody` refactors).
- Web unit tests: `web/scripts/partner-view.test.mjs` (NEW: the rules and every partner string verbatim, both halves of `partnersHelp`); `settings-view.test.mjs` (the section list; the hide rule for an absent `partner-contacts` member); `settings-refusal-sources.test.mjs` (`SAVING`); `announce-focus-sources.test.mjs`; `ux-strings.test.mjs` (SOURCES).
- `web/e2e/settings/partner-contacts.spec.ts` -- NEW, serial, real stack. A `page.route` on `**/api/v1/settings**` fetches the real response and adds `sections['partner-contacts']` from `SettingsOps.PartnerValues()` read by `irisScript` (the TABLE 1 state; the POSTs reach the real route and rows). `afterAll` removes the `zz` contacts. P1: nav, heading, `partnersHelp` verbatim, labels, keyboard; P2: add, then the stored row and the audit entry; P3: a bad address and no production mark both fields, focus the address, nothing changes; P4: edit, then remove with the confirm.
- `web/e2e/api/partner-contacts.spec.ts` -- NEW, real HTTP: H1 a LIVE `OcuTalonUser` gets 403 on the POST; H2 an admin add is 200, the GET has the member exactly when the real `TABLE` is 1, and `ForProduction` returns the contact in a fresh `irisScript`; H3 a bad address is 400 `["email"]`; H4 a remove empties `ForProduction`.
- `web/e2e/settings/settings.spec.ts` and `on-call.spec.ts` -- S1/S1f/O6 lists and counts include "Partner contacts" exactly when the real GET carries the member (state-derived, so 23.13's `TABLE = 1` needs no edit here).

**Acceptance Criteria:**
- AC1. Given TABLE 1 and an admin on Partner contacts, when they add, edit or remove a contact, then `SettingsOps` writes or deletes its row, one `Settings` audit entry `partnerContact.<Ref>` names the changed fields (written first, in one transaction, with the admin and the session), and the page shows "Saved. Applies within a minute. Recorded in the audit log." with the list updated.
- AC2. (Integration: consumer `Data.PartnerContact.ForProduction`, the reader 23.13 switches to.) Given saved contacts, when a fresh process calls `ForProduction(namespace, production)`, then it returns exactly the stored contacts naming that pair, as `[{id, name, address}]` in ID order, and an edited-away or removed contact is gone at once.
- AC3. Given an invalid name, address or production list, when the admin saves, then each field shows its accepted error, focus moves to the first, and nothing is written or audited (UX-DR36).
- AC4. (DW-1254, veto 3.) Given a saved and then removed contact through the real production, when the leak scan runs, then the name and the address are in no audit row, message body, `Ens.MessageHeader`, event-log row, trace global or `^OcuTalon*` global but `OcuTalonP.PartnerContactD` while the row exists, and nowhere after the remove; `SaveSettings.Changes` is exactly `{handoff}`.
- AC5. Given `TABLE` is not 1 (feature today), when Settings loads, then GET has no `partner-contacts` member and the page neither lists nor opens the section.
- AC6. Given `TABLE` is 1, when Settings loads, then GET has the member and the section shows "Partner contacts" with `settings.partnersHelp` verbatim.
- AC7. Given `ListProductions`, when it is submitted from `web_admin`, then `SettingsOps` answers the productions within the 20 s wait; from any other origin, or inside a bridge context, it is `not_allowed` and nothing is sent; on the demo it is `not_available`.
- AC8. Given a non-admin, when they call the route, then it is 403 `not_admin`. Given the online demo, when an admin calls it or loads Settings, then it is 409 `not_available` with `partnersOffOnDemo` before the body is read, GET has no member, and nothing is written.
- AC9. Given the Playwright spec, when the section is used by keyboard alone, then every control is labelled, Remove names its contact, and the stored contacts and audit entries match what was submitted (NFR-25, UX-DR130).

## Spec Change Log

- 2026-11-15 (lead). **Gate ruled, Contest Planner ~16:30Z Nov 15 (BINDING; corrected by the orchestrator: the Lane A story is 23.13, not 23.10)**, quoted in full from `<coordination>/prompts/story-242-rulings-20261115.md`:

  > # Story 24.2 rulings (Contest Planner, ~16:30Z Nov 15). BINDING.
  > 
  > ## G1: (B), SPLIT
  > This also answers the size and multiple-goals warnings.
  > - 24.2 is partner contacts ONLY.
  > - New story 24.5 is saved SQL query watches in Settings. It depends on 23.8, and its plan starts after 23.8 merges. Charter it in epics.md, marked [ADDED 2026-11-15, Contest Planner split of 24.2]. Record its wait in epic-dependencies.yaml only through the orchestrator.
  > - No hidden section that switches itself on at runtime, and no route that answers "isn't built yet".
  > 
  > ## G2: (a), with one change: NO "not yet" text
  > - 24.2 builds the table, the save path, the ForProduction reader and the leak-scan test.
  > - The Settings section stays HIDDEN until Fix.PartnerContacts has `TABLE = 1`, so the TABLE parameter is the switch. Pin both states:
  >   - at 0, the section is hidden;
  >   - at 1, the section is shown with the approved settings.partnersHelp.
  > - settings.partnersNotYet is REFUSED.
  > - APPROVED as a veto item: the reader switch and DW-1254's contact-id change move to Lane A's Story 23.13. Lane A sets `TABLE = 1` in 23.13.
  > 
  > ## Veto items
  > 1. **ListProductions: APPROVED.**
  >    - Read-only and web_admin only.
  >    - Runs in SettingsOps with a 20 s limit.
  >    - On the demo it answers not_available.
  >    - Not usable by tools. PIN this.
  > 2. **The TABLE parameter as the cross-lane contract: APPROVED**, as above.
  > 3. **Audit: CHANGED.**
  >    - The audit records partnerContact.<Ref> and WHICH fields changed (name, email, productions), never their values. A contact's name and email must leave with the contact, and the IRIS audit log can't be purged per contact.
  >    - Keep SecretHandoff and the leak scan, and EXTEND the leak scan to the audit rows.
  > 4. **The route bodies and ForProduction's shape as spine bullets: APPROVED.**
  > 
  > ## Scope
  > - GRANTED for the contacts half only: the extensions beyond Epic 24's declared paths (Msg/Command/, Web/ classes other than Api.cls, Test/Msg/, short-names.tsv, web/scripts/).
  > - Target: 1.0.12 or later.
  > - On the demo: the routes answer 403 and 409, and both sections are hidden.
  > 
  > ## 23.13 replaces "23.10" (Contest Planner, ~16:45Z). BINDING.
  > 23.10 is already done, so a new story, **23.13 "Partner warnings go to the Settings contacts"**, replaces it everywhere above.
  > - **Files and runner:** Lane A files, run by lane B (Epic 23's runner).
  > - **Scope:**
  >   - the Fix.PartnerContacts reader switch;
  >   - DW-1254's contact-id change in 23.5's warnings;
  >   - TABLE = 1.
  > - **Charter:** lane B charters it in epics.md with an [ADDED 2026-11-15, Contest Planner] marker.
  > - **When:** after 23.4 and 23.8, and only once 24.2 has merged.
  > - **Acceptance criteria:**
  >   - the 24.2 Settings section shows only when TABLE = 1;
  >   - a warning goes only to the contacts set for that production;
  >   - the leak scan still passes.

  Applied by the lead: `epics.md` narrows 24.2 to partner contacts with an `[AMENDED 2026-11-15 ...]` marker and charters Story 24.5 (saved SQL query watches; waits for 23.8) with an `[ADDED 2026-11-15, Contest Planner split of 24.2]` marker. Status reset to `draft` for a re-plan of the narrowed scope.

- 2026-11-15 (plan stage, re-plan). **Intent block amended to the binding rulings above.** Original: the intent covered both halves (partner contacts and SQL query watches), with a `SqlBuilt()`-gated SQL section and a 501 `not_built` route, a partner section shown with a proposed `settings.partnersNotYet` line while `TABLE` was absent, and an audit entry per field holding from and to VALUES (`partnerContact.<Ref>.name|.email|.productions`). Amended: partner contacts only (G1 (B)); the section hidden unless `TABLE = 1`, both states pinned, no "not yet" text (G2 (a)); one audit entry `partnerContact.<Ref>` naming the changed fields, never values, with the leak scan extended to the audit rows (veto 3); `ListProductions` pinned as no tool verb (veto 1). Every SQL item is recorded under Design Notes › Moved to Story 24.5. Known-bad state avoided: a hidden section or route that switches itself on, and contact values in an audit log that cannot be purged per contact. KEEP: the SecretHandoff path, `Changes` exactly `{handoff}`, the leak scan and `ForProduction`'s shape.

## Review Triage Log

### 2026-11-15 — Review pass
- verdicts: 29 findings — high 0, medium 5, low 23, false 1, maybe-false 0
- findings:
  - `[low]` `[reject]` Blind 1: productions text over the 4000-character MAXLEN fails the save as a generic `failed` — needs about 50 listed productions; the failure rolls back and changes nothing; the fix adds a guard. wontfix-accepted, reopen_if an instance lists 50 or more productions.
  - `[low]` `[reject]` Blind 2: an empty or failed roster gives no message — a message is new public text, which this story may not ship (only the approved strings); the section still refuses with the approved `partnerNoProduction`.
  - `[low]` `[reject]` Blind 3: duplicate names or addresses are accepted — no AC or matrix row refuses them, it is the admin's choice, and a recipient list that repeats an address is the consumer's (23.13's reader) to de-duplicate; noted under residual risks.
  - `[low]` `[reject]` Blind 4: two bounded round trips on one GET at TABLE 1 with a wedged production — Decided in-stage 4 and 7 chose this shape, mirroring `OnCallRoster`; by-design.
  - `[low]` `[reject]` Blind 5: a 409 on Remove swaps the dialog text only — the section is absent on the demo, so only a stale page reaches it, and the text is correct; the fix adds a branch for an unlikely path.
  - `[low]` `[reject]` Blind 6: `partnerBadName` does not name the `@{` and control-character causes — the string is the approved text, verbatim by the spec; spec-bound, by-design.
  - `[low]` `[reject]` Blind 7: a no-change save shows "Recorded in the audit log" — the matrix row "Nothing changed" is 200 done with the reused saved text; spec-bound, by-design.
  - `[low]` `[reject]` Blind 8: server and browser trim differently for NBSP — an admin must type a non-breaking space; the stored value is only a blank-looking name; unlikely, and the fix adds normalisation on both sides.
  - `[medium]` `[patch]` Blind 9: the bridge-context refusal of `ListProductions` has no recorded mutation — patched: origin gate in `CommandsIn.Carry` mutated, `TestListProductionsRouting` and `TestContextMeansTool` red, reverted with `cmp`; its line is in `## Verification`. (The stale `## Auto Run Result

## Design Notes

### Moved to Story 24.5 (G1 (B))

- The SQL query watches section and its nav entry: moved to Story 24.5.
- The route `POST /api/v1/settings/sql-watches` and `Web.SqlWatchSettings.cls`: moved to Story 24.5.
- `SqlBuilt()`, the 501 `not_built` answer and the "23.8 finding" on today's `failed`: moved to Story 24.5 (its plan starts after 23.8 merges, so neither is needed).
- `SqlWatchRows` and the `CheckRows` generalization of `SourceRows`: moved to Story 24.5.
- `sql-view.ts`, `sql-watches-section.ts`, `keepSqlWatches`, the rail-view `sql_query` case: moved to Story 24.5.
- `SqlWatchSettingsProbe`/`SqlWatchSettingsApi`, `web/e2e/settings/sql-watches.spec.ts`, `web/e2e/api/sql-watches.spec.ts`: moved to Story 24.5.
- `Values(sessionRef)` and Api passing `Ownership.SessionRef` (needed only for own SQL rows): moved to Story 24.5.
- Matrix rows SQL not built, SQL save, SQL refused, SQL bad shape, SQL remove; ACs 5-8 of the earlier plan and the SQL half of AC9-AC10: moved to Story 24.5.
- Public text `settings.sqlSection`/`sql*`, `settings.sqlOffOnDemo`, the reuse of `settings.onCallBadMinutes` and "Check every", the condition on `settings.sqlHelp`: moved to Story 24.5.
- Decided-in-stage items 6-8 and 10 of the earlier plan (no SQL edit, refusals under Query, minutes 1-1440, query text in the trace): moved to Story 24.5.

### Moved to Story 23.13 (G2 (a), ruled)

- Switching 23.5's reader (`Fix.PartnerContacts.For`/`Named`) to `ForProduction`, DW-1254's contact-id change in Lane A's partner messages, and `Parameter TABLE = 1`. 24.2 only reads `TABLE`.
- The epics AC "these contacts are the only addresses a partner warning ... can ever be sent to" is delivered by 23.13 (its ruled AC: a warning goes only to the contacts set for that production).
- `settings.partnersHelp`'s condition (pin both halves): 24.2 pins the text verbatim and that it shows only at `TABLE = 1`. The behaviour behind "only to the people listed here" is pinned by 23.13's ruled AC, and "only after you approve each one" by 23.5's approval path (a partner warning is an approval-gated fix request; inference from 23.5's spec, not re-measured here). The text cannot show before 23.13 sets `TABLE`.

### Decided in-stage

1. The route is a forwarded Map, as 36.4's was; Api's `TestRoutes` still counts 38.
2. One contact per save (save or remove), matching the per-contact Add, Save changes and Remove texts.
3. Audit form (veto 3): one entry per save or removal; from = the changed fields that held a value before, to = the changed fields that hold one after, comma-joined in name, email, productions order. So an add is from "" to `name,email,productions`, a removal the reverse, and an edit of the address `email` to `email`. No value, no new word, and `Bridge.Audit` describes it as "Setting partnerContact.<Ref> changed".
4. `GET /v1/settings` carries the member only while the section is shown, so nothing is read or sent for a hidden section (no `ListProductions` submit on each load at TABLE 0). The route and the saver ignore `TABLE`: 24.2 builds the save path now, the api spec proves it today, and 23.13 needs no route change.
5. `PartnersShown` takes the class name with `Fix.PartnerContacts` as default, so a test pins both values against test classes that declare `TABLE`, and the real-class assertions are state-derived and survive 23.13.
6. The Playwright UI spec simulates only the TABLE 1 state: it adds the member read from the real `PartnerValues()` (irisScript) to the real GET and POST answers; rows, audit and routes are real. Task 0 measures that `irisScript` can run it.
7. Productions come through `ListProductions` (`Reader.Productions()` needs the production job); production names are not personal data, so its `Data` is inline, as `ListMcpServers`' is. Ruled as veto 1.
8. The contact list is read in the web process only through `PartnerContact.List()` (AD-13, L484). The `web-global-reads` baseline is unchanged.
9. Nav order: On call, then Partner contacts. Remove always asks `partnerRemoveConfirm`, because the section shows only while warnings use the table.
10. The spec keeps its file name and title, which still name SQL watches: they are the sprint key and the `epics.md` title. A retitle is the lead's call (Rule 5's sprint-key step).

### Governing ADs (Rule 6)

AD-1 (commands, `ListProductions`), AD-3 (the private global from `short-names.tsv`), AD-13 (admin routes; web reads only through the owning class), AD-17 (`Bridge.Audit` is the only writer), AD-19 (step-5 sections, `SecretHandoff`; V3 narrowed for partner contacts by veto 3), AD-24 (personal data out of the trace), AD-25 (the online demo), AD-29 (lanes; no Lane A edit), AD-33 (one writer per table).

### Integration ACs, Consumed-by, Consumes (Rules 1, 2)

- **Integration AC:** AC2 (`ForProduction` read in a fresh process, as 23.13's reader will).
- **Consumed-by:** 23.13 (`ForProduction` and the `TABLE` switch); 24.4 (a partner warning's recipients, through 23.5's reader once 23.13 switches it).
- **Consumes:** `SecretHandoff`, `Bridge.Audit.Record`, `Watch.Reader.Productions` (through the verb), `CommandsIn`, 36.4's `Web.OnCallSettings` and `SaveOnCall` prologue.

### Extend, don't copy (Rule 2)

- `Web.PartnerSettings` extends `Web.OnCallSettings`, whose `Slug` and `OffText` become overridable.
- `SavePartner` shares `HandoffBody`, extracted from `SaveOnCall`.
- `ProductionsRoster` copies `OnCallRoster`'s shape: one answer is inline, the other a handoff.
- `WritePartner` copies `SaveProduct`'s transaction, because it writes a row, not `Apply` keys.
- `ListProductions` copies `ListOnCallUsers`. The leak scan reuses 36.4's helpers (`Leaks`, `TraceLeaks`, `LogText`, `TableHolds`); `TableHolds` is copied into the new test class as 36.4's is private, the reason being one helper of 12 lines.

### Ledger (Rule 17)

`LEDGER slice 24-2-set-partner-contacts-and-saved-sql-query-watches-in-settings` holds DW-1254.
- **Addressed:** the handoff, `Changes` exactly `{handoff}`, the leak scan (AC4). Its "values reach only the IRIS audit entry" is superseded by veto 3: values reach only the row, and the scan covers the audit rows.
- **Residual:** the contact-id change in Lane A's partner messages is 23.13's (ruled), so DW-1254 is not fully `resolved-by` 24.2; at adjudication the lead re-owns the residual to 23.13's key.

### Spine updates for the lead (Rule 20; vetoes 2 and 4 approved)

- L767: partner contacts' audit holds `partnerContact.<Ref>` and the changed field names, never values (veto 3).
- L770-772: `partner-contacts`' body `{action, ref, name, email, productions}` / `{action, ref}` and its 200/400/403/409/500 answers; the section is shown only while `Fix.PartnerContacts` `TABLE = 1` (the cross-lane contract, 23.13 sets it); `sql-watches` becomes Story 24.5's.
- L1560: `ForProduction(namespace, production)` returns `[{id = row ID, name, address}]` in ID order.
- Beside L1631: the `ListProductions` row (web_admin only, SettingsOps, 20 s `busy`, inline `Data {"productions"}`, no tool verb, not counted by the evaluation or the allowance).
- Then `memlog.py append`, `lint_spine.py` and a refreshed `updated:`.

### Release

Target 1.0.12 or later. On the online demo the route answers 403 to visitors and 409 to an admin, and the section is absent.

## Public text

No NEW user-facing string. Shipped verbatim from EXPERIENCE.md › Settings (step 5): `settings.partnersSection`, `partnersHelp` (shown only at `TABLE = 1`), `partnerName`, `partnerEmail`, `partnerProductions`, `partnerAdd`, `partnerRemove`, `partnerRemoveConfirm`, `partnerBadName`, `partnerNoProduction`, `partnersOffOnDemo`, and `settings.badEmail`. Reused as they are: "Save changes", "Saved. Applies within a minute. Recorded in the audit log.", "Couldn't save. Nothing was changed.", "Cancel" (`MCP_TEXTS.cancel`). `settings.partnersNotYet` is refused and is not shipped.

## Veto items

None new. Ruled (Contest Planner, ~16:30Z Nov 15): (1) `ListProductions` APPROVED, pinned as no tool verb (AC7); (2) the `TABLE` parameter as the cross-lane contract APPROVED; (3) the audit CHANGED to ref and field names, applied (AC1, AC4); (4) the body contracts and `ForProduction`'s shape as spine bullets APPROVED (Spine updates above). Scope extensions GRANTED for this half: `Msg/Command/`, `Web/PartnerSettings.cls` and the `Web/OnCallSettings.cls` refactor, `Test/Msg/`, `short-names.tsv`, `web/scripts/`. No new role, grant, resource, retention rule, outward action, web dependency or online-demo capability.

## Verification

Every IRIS call runs from the worktree root with `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-d" OCUTALON_TEST_WEB_PORT=52804 OCUTALON_LOCK_OWNER='epic=24 stage=implement'`. Warm tag `e24s2iw`, fresh tag `e24s2i`. Each line is one foreground call (`timeout: 600000`) that ends inside about 150 s; one test class per call, never two test calls in one message. The web suite and each Playwright part are calls of their own.

**Shared surfaces:** the Settings section list (`SETTINGS_SECTIONS`) and its nav count (state-derived for Partner contacts); the GET `/v1/settings` `sections` keys (`SettingsSave:441`); the `CommandsIn` Routes table and the verb lists in `CommandsRouting` and `Contracts`; `short-names.tsv`; the `ux-strings`, `settings-refusal-sources` and `announce-focus-sources` lists; `settings.spec.ts` S1/S1f and `on-call.spec.ts` O6.

Standing criterion: every test added or changed passes on a fresh environment, in either order.

**Commands:**
- (once) `npm ci` in `web/` (`npm --prefix web ci`) -- this fresh worktree has no `web/node_modules`; the implement stage installs them first.
- (once) `... OCUTALON_RUN_TAG=e24s2iw ci/warm.sh up` -- ready.
- (loop) `... OCUTALON_WARM=1 OCUTALON_RUN_TAG=e24s2iw ci/iris.sh class <C>`, one call each for `OcuTalon.Test.Core.SettingsPartners`, `Test.Web.PartnerSettingsApi`, `Test.Web.OnCallSettingsApi`, `Test.Core.SettingsOnCall`, `Test.Core.CommandsRouting`, `Test.Msg.Contracts`, `Test.Core.SettingsSave` -- each prints `CLASS … passed`. After a `SettingsOps` change, restart the item as 36.4's notes say.
- (once) `... OCUTALON_RUN_TAG=e24s2iw ci/warm.sh down`.
- (once) `... OCUTALON_RUN_TAG=e24s2i ci/iris.sh class OcuTalon.Test.Web.PartnerSettingsApi` -- passes on a fresh stack (the leak scan in the real production).
- (loop) `npm --prefix web test` -- passes. Then (once) `npm --prefix web run lint` and (once) `npm --prefix web run build` -- pass with no budget error.
- (once) `... OCUTALON_RUN_TAG=e24s2i ci/iris.sh build`; then (once each) `ci/iris.sh live sign-in-2 --part k/N` for the part holding `partner-contacts.spec.ts`, then the part(s) holding `settings.spec.ts` and `on-call.spec.ts`; then `ci/iris.sh live sign-in --part k/N` for `api/partner-contacts.spec.ts`. Find k/N with `npm --silent --prefix web run e2e:sign-in-2 -- --list --reporter=json` (or `e2e`) and `node web/scripts/e2e-part.mjs`, choosing N so each part ends inside about 150 s -- all pass.
- (once) `bash docker/tests/test-class-rules.sh`, (once) `bash docker/tests/test-ci-config.sh`, (once) `bash docker/tests/test-boundaries.sh` -- pass. (once) `... ci/iris.sh live storage-roundtrip` -- passes (the new storage block).
- (once) `... OCUTALON_RUN_TAG=e24s2i ci/iris.sh teardown`.
- (once) Fresh-environment check (the lead): `ci/iris.sh shard lane-b --part k/n` and `--reverse` for the parts holding the added classes, each inside about 150 s.

**Mutations (Rule 19; record each as `mutation: … → …`):**
- AC1: skip `WriteAudit` in `WritePartner` → `SettingsPartners.TestAddEditRemoveAudited` red.
- AC2: drop the namespace match in `ForProduction` → `TestForProductionOnlyStoredContacts` red.
- AC3: accept `productions` [] → `TestRefusalsNameFieldsOnly` red.
- AC4: put the address in the audit entry's `to` → `PartnerSettingsApi.TestValuesOnlyInTheRow` red (and: put the body in `Changes` → the same test red).
- AC5: `PartnersShown` returns 1 → `SettingsPartners.TestTableStates` red; drop `partner-contacts` from the page's hide rule → `settings-view.test.mjs` hide case red.
- AC6: `Values` omits the member when shown → `TestSectionShownAtTableOne` red; drop the help line → `partner-view.test.mjs` / `partner-contacts.spec.ts` P1 red.
- AC7: add `ListProductions` to `TOOLVERBS` → `CommandsRouting.TestListProductionsRouting` red.
- AC8: move the demo check after the body read → `PartnerSettingsApi.TestOnlineDemoRefusesFirst` red.
- AC9: remove the Name label → `partner-contacts.spec.ts` P1 red.

**Manual checks:** none beyond the commands.

**Mutations demonstrated at implement (restored by the lead from the stage's report; the implement finalize dropped this section):**
- mutation: `PartnersShown` always 1 → `TestTableStates` red (TABLE 0 state).
- mutation: `PartnersShown` always 0 → `TestTableStates` red (TABLE 1 state).
- mutation: `partner-contacts` dropped from the page's `VALUE_SECTIONS` → `settings-view.test.mjs` red (hide rule).
- mutation: `Values` never adds the member → `TestSectionShownAtTableOne` red.
- mutation: the second half of `partnersHelp` cut → `partner-view.test.mjs` red.
- mutation: `ListProductions` added to `TOOLVERBS` → `TestListProductionsRouting` red (not usable by tools).
- mutation: the origin gate in `CommandsIn.Carry` changed → `TestListProductionsRouting` and `TestContextMeansTool` red (bridge context).
- mutation: the address put into the audit entry's `to` → `PartnerSettingsApi.TestValuesOnlyInTheRow` red (leak scan over audit rows).
- mutation: the name put into `Changes` → `TestValuesOnlyInTheRow`, `TestCommandHoldsOnlyTheHandoff`, `TestBadBody` red.
- mutation: the audit write skipped → `TestAddEditRemoveAudited` red.
- mutation: the namespace match dropped → `TestForProductionOnlyStoredContacts` red.
- mutation: empty `productions` accepted → `TestRefusalsNameFieldsOnly` red.
- mutation: the demo check moved after the body read → `TestOnlineDemoRefusesFirst` red.
- mutation: the demo guard on the member in `Values` dropped → `TestOnlineDemo` red.
- mutation: the Name label's `for` removed → Playwright P1 red.

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** Partner contacts in Settings: `Data.PartnerContact` (private global, `ForProduction`, `List`, `RefOpen`), `SettingsOps` as its only writer (`SavePartner`/`WritePartner`: handoff only, whole-body validation, one audit entry `partnerContact.<Ref>` naming the changed fields, written first in one transaction), the web_admin read verb `ListProductions` (20 s `busy`, `not_available` on the demo, no tool verb), the route `Web.PartnerSettings`, and the Settings section, shown only while `Fix.PartnerContacts` has `TABLE = 1` (absent today, so it is hidden). No SQL code, no "not yet" text, no Lane A file, no `TABLE = 1`.

**Files changed.**
- `src/short-names.tsv`, `Data/PartnerContact.cls` (new): the table and its readers.
- `Msg/Command/ListProductions.cls` (new), `Core/CommandsIn.cls`: the verb, its route row and bounded send.
- `Core/SettingsOps.cls`: the section row, `PartnersShown`, `PartnerValues`, `ListProductions`, `HandoffBody` (extracted from `SaveOnCall`), `SavePartner`, `WritePartner`, the audit form.
- `Web/OnCallSettings.cls` (`Slug`/`OffText` overridable), `Web/PartnerSettings.cls` (new), `Web/Api.cls` (one Map line).
- IRIS tests: `Test/Core/SettingsPartners.cls`, `Test/Web/PartnerSettingsApi.cls`, `Test/Web/PartnerSettingsProbe.cls` (new); `SettingsOpsProbe`, `CommandsRouting`, `Contracts`, `SettingsSave` extended.
- Web: `partner-view.ts`, `partner-contacts-section.ts` (new); `settings-view.ts`, `settings-page.ts`, `api-types.ts`, `api-client.ts`.
- Web tests: `partner-view.test.mjs` (new) and the section-list tests `settings-view`, `settings-refusal-sources`, `announce-focus-sources`, `ux-strings`, `mcp-view`, `floor-sources`; e2e `settings/partner-contacts.spec.ts` (P1 to P7), `api/partner-contacts.spec.ts` (H1 to H4), `support/partner-contacts.ts` (new); `settings.spec.ts`, `on-call.spec.ts`, `roles.spec.ts`, `deep-link.spec.ts` made state-derived for the section.

**Review.** Four layers, 29 findings: high 0, medium 5, low 23, false 1. Patches applied (5 entries): the bridge-context mutation, P5 to P7 (500, 409, 403), a deterministic `TestListProductionsVerb`, a self-contained P4, and the AC7/AC8 mutation lines. Deferred (1): the rollback after a failing row write is unpinned. Rejected (23 low, 1 false): each with its reason in the Review Triage Log. Patched counts: high 0, medium 4, low 1.

**Follow-up review recommended: true.** Unverified risk: the patched web tests ran once (P1 to P7 in `sign-in-2` part 17/20, 7 passed); P4's independence was reasoned and not run alone.

**Verification.** `npm --prefix web test` 2136 pass; lint, build (initial 889.05 kB), `test-class-rules.sh`, `test-ci-config.sh`, `test-boundaries.sh` and `live storage-roundtrip` pass; warm classes `SettingsPartners`, `PartnerSettingsApi`, `OnCallSettingsApi`, `SettingsOnCall`, `CommandsRouting`, `Contracts`, `SettingsSave`, `Web.SettingsApi` and `Web.Api` pass; `PartnerSettingsApi` and `SettingsPartners` pass on a fresh stack; live `sign-in-2` parts 16 to 18 and 14 of 20 and `sign-in` part 5 of 32 pass. Every mutation of `## Verification` was seen red and reverted byte-identically (`cmp`), among them `PartnersShown` always 1 and always 0 (TABLE 0 and TABLE 1), `ListProductions` in `TOOLVERBS` (tool refusal), the bridge-context gate, and an address put into the audit entry (`TestValuesOnlyInTheRow` red, the leak scan over the audit rows). All stacks are torn down.

**Residual risks.**
- Duplicate names or addresses are accepted: 23.13's reader should de-duplicate recipients.
- With the production wedged and `TABLE = 1`, a Settings GET can wait up to two bounded waits.
- The handoff subagent sent two class runs in one message once (`SettingsSave` and `Contracts`); both passed and nothing raced.
- The `TABLE = 1` page state is simulated by a route in the browser specs; its real state arrives with Story 23.13.
- The Lane D spec edits `roles.spec.ts`, `deep-link.spec.ts`, `mcp-view.test.mjs` and `floor-sources.test.mjs` are shared-surface updates beyond the spec's list.
