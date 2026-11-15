---
title: 'Story 23.13: Partner warnings go to the Settings contacts'
type: 'feature'
created: '2026-11-15'
status: 'draft'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-23-context.md'
warnings: [oversized]
deferred: []
---

<intent-contract>

## Intent

**Problem:** Story 23.5's partner warnings still read Lane A's demo-only fixture (`Fix.PartnerContacts`). The contacts an admin sets in Settings (Story 24.2's `Data.PartnerContact`) are never used, and the Settings › Partner contacts section stays hidden, because `Fix.PartnerContacts` declares no `TABLE`. The warning's traced messages also carry contact names and addresses (the draft's facts, the `to` parameter, the dry run, the approval request's chat text). DW-1254 forbids that once the contacts are real people.

**Approach:**
- `Fix.PartnerContacts` declares `TABLE = 1`. This shows the Settings section.
- The reader chooses its source by production:
  - the demo's own production keeps its fictional fixture, while demo mode is on;
  - every other production reads the Settings contacts, de-duplicated by address;
  - the online demo never reads the table.
- Every traced message names contacts by id only. The production job resolves the ids to names and addresses into the approval row, so the approver sees them on the card.
- **[AMENDED 2026-11-15, Contest Planner 23.13 GATE ruling (prompts/story-242-rulings-20261115.md "23.13 GATE"), veto 2 CHANGED; BINDING]** An approved partner warning to Settings contacts is SENT through Story 21.11's EmailOut path, from the mailbox connected in Settings > Channels > Email: one approval, sent exactly once. It is kept as an approved draft ONLY when no mailbox is connected, and its texts then say so truthfully. If the EmailOut path CAN'T carry it, STOP: name the file and line and say why, before building a kept-draft-only version (HALT `blocked`, `intent gap`). Texts: the kept path uses the Planner's conditional wording verbatim (see Design Notes "Planner rulings, 23.13 GATE"); the SENT path reuses 21.11's approved email texts where they fit; ANY new line is NEW public text for the Planner (list it under the gate, verbatim). The online demo is unchanged (no Settings contacts, nothing sent; fictional contact to the Simulated mailbox).

## Boundaries & Constraints

**Always:**
- **The source rule.** `Fix.PartnerContacts.For(production, namespace)` decides the source:
  - The **fixture** applies when the fixture names the production (`OcuTalon.Demo.Orders.Production`), and only while demo mode is on. Its contacts are fictional, its requests have `simulated` 1, and it is delivered to the Simulated mailbox exactly as in 23.5. The table is never read for that production.
  - The **table** applies to every other production: `Data.PartnerContact.ForProduction(namespace, production)`, de-duplicated by lower-cased trimmed address (the lowest id is kept, ID order), giving `simulated` 0.
  - On the online demo (`Watch.Reader.OnlineDemo()`), the table branch returns `[]` without reading the table.
- **The `to` parameter.** It keeps its name (AD-16) and becomes the comma-separated contact ids, ascending, equal to the targets. `CheckParameters` accepts only a list of positive whole numbers.
- **The dry run.** The kind's dry run, which goes in the traced `DryRunResult`, is `{"notice", "recipients": [<id>, ...], "simulated"}`.
- **What the approver sees.** Before `AskedSlots` and `RaiseFix`, `IncidentManager` calls one new `Fix.Kind` hook. It resolves the ids to `[{id, name, address}]` in the production job. The approval row's `DryRun` (stored, never traced) and the approval card (`Live.Payload.Approval`, unchanged) show the names and addresses.
- **Facts.** The draft's facts hold no contact name or address. The "Partner:" line goes. `SYSTEMNOTE`'s first sentence becomes "Write a short delay notice to a partner about the failures described below.", and the CI mock B prompt moves with it.
- **Settings-contact requests (simulated 0):**
  - They use the NEW key `incident.partnerRequestKept`, with slots `production` and `notice` and no recipient names.
  - `Ready` is 0 with `NOTSETUP` whether demo mode is on or off. An approved request is kept as an approved draft (`result.partnerKept`), with no `PartnerNotice` and no Simulated mailbox copy.
  - `Recheck`/`Execute` never give a delivery for one: each target is skipped with `NOSTART`, as defence in depth.
  - The Action audit target drops " (simulated)" for them.
- **Other text for Settings-contact requests.** The Telegram press reads `press.approvedPartnerKept`. The web card's pending note reads `APPROVAL_TEXTS.partnerKeptNote`.
- Reuse the 24.2 leak-scan helpers (`Test.Core.SecretHandoff.Leaks` and `TraceLeaks`, `Test.Bridge.AuditLog.Entries`, `Test.Web.WebhookTools.LogText`).
- In every added test, create and remove its own contact rows (Name prefix `zzpc`, `%DeleteId` in `OnAfterOneTest`).

**Never:**
- Edit Lane B's contracts: `Data.PartnerContact`, `Core/SettingsOps.cls`, `Web/PartnerSettings.cls`, `Web/Api.cls`, `web/src/app/settings/**`.
- Read the table on the online demo, or from the web process.
- Send to a Settings contact through any channel, the Simulated mailbox included.
- Put a Settings contact's name or address into a traced message (Draft/Decide input, `DryRun`, `DryRunResult`, `Notification`, `FixResult`, `PartnerNotice`), a log line, an audit entry or `FixRun.Reason`.
- Change the demo's approved texts or its "Warn the partner" flow.
- Touch `Fix/Executor.cls`, `Watch/IncidentManager.cls` or `Watch/Notice.cls` beyond the hooks listed in the Tasks.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| SETTINGS_HAPPY | Local install; production `ZZPROD` (namespace `ZZNS`) has Settings contacts A (id a) and B (id b); a warning is asked | The request has `to` = targets = "a,b" and a dry run with `recipients` [a, b] and `simulated` 0. The row `DryRun` holds `[{a, nameA, addrA}, {b, ...}]`. The card shows "To: nameA <addrA>, nameB <addrB>". The Notification key is `incident.partnerRequestKept` with no name. | none |
| DEDUPE (DW-1393) | Contacts 3 and 5 both list `ZZPROD`, with addresses `X@Y.example` and ` x@y.example` | One recipient, id 3, and targets "3" | none |
| OTHER_SCOPE | A contact lists `ZZPROD` under another namespace, or another production | Not a recipient | none |
| NO_CONTACTS | `ZZPROD` has no Settings contact | `AskedDraft` refuses with `NOCONTACTS`; nothing is drafted or raised | refusal text |
| KEPT | The Settings-contact request is approved, demo mode on or off | Could not start with `NOTSETUP`; the row keeps its text; no mail, no `PartnerNotice`; the session gets `result.partnerKept`; Telegram press is `press.approvedPartnerKept`; the Action target is "2 partner contacts (a,b) of ZZPROD" | none |
| EXECUTE_GUARD | `Recheck`/`Execute` are called directly on a Settings-contact request | `deliveries` []; each target skipped with `NOSTART` | none |
| DEMO_FIXTURE | The Orders production with demo mode on (local or online demo), even with a Settings contact listing it | As in 23.5: contact 1 "Orders Partner IT", `simulated` 1, `incident.partnerRequest` naming it, Simulated mailbox after approval byte for byte | none |
| DEMO_OFF | The Orders production with demo mode off | `NOCONTACTS`; nothing is drafted | refusal text |
| ONLINE_DEMO_TABLE | The online-demo flag is on; a table row (written directly) lists `ZZPROD` | `For` gives []; the table is not read | `NOCONTACTS` |
| TAMPERED | A row whose `to` is an address, or ids that are not the targets | `CheckParameters` refuses; every target is `NOSTART`; nothing is sent | none |
| NO_APPROVAL | `Execute` with no approved row | Nothing is sent or kept beyond today's per-kind refusal | none |

</intent-contract>

## Code Map

Lane A (edit freely):
- `src/ocutalon/cls/OcuTalon/Fix/PartnerContacts.cls`.
  - The XData fixture is at 13-18. `For` 21-32 (demo-only), `Named` 35-43, `Addresses`/`Names`/`Joined` 46-66, `All` 69-86.
  - Add `Parameter TABLE = 1`, a `Simulated(production)` predicate, the table branch, the de-duplication and an `Ids` helper. `Ids` reuses `Joined`.
- `src/ocutalon/cls/OcuTalon/Fix/Kind/PartnerWarning.cls`.
  - Class doc 1-14. `SYSTEMNOTE` 41. `NOTSETUP`/`NOCONTACTS`/`RECHECK`/`NOSTART` 43-57.
  - `Facts` 61-83: the Partner line is at 71.
  - `CheckParameters` 170-180 and `AddressList` 183-189.
  - `DryRun` 193-212. `Ready` 221-227. `Recheck`/`Execute`/`Plan` 231-278.
  - `ProductionName` and `Reason` 215-218 are reused for the kept slots.
- `src/ocutalon/cls/OcuTalon/Fix/Kind.cls`.
  - `ForName` 113 and base `Ready` 261 are the sibling pattern for the new hook `ForApprover(incident, dryRun)`. The base returns `dryRun` unchanged.
  - Add a dispatcher `Shown(kind, incident, dryRun)` that uses `ForName`.
- `src/ocutalon/cls/OcuTalon/Msg/Catalog/Watch.cls` 960-1045 (the partner keys). `incident.partnerRequest` 960-968 is the shape to copy, with `text` and `web`.
- `src/ocutalon/cls/OcuTalon/Msg/Catalog/Core.cls` 907-911: `press.approvedPartner`.
- `src/ocutalon/cls/OcuTalon/Channel/Telegram/In.cls`. `FromTelegram` slots 480-491 come from `Live.Payload.Approval.FromRow(row).DryRun`. Add `simulated` for `partner_warning`. `PressText` 514-515 picks the key.
- `web/src/app/approvals/approval-view.ts`: doc 30-33, `APPROVAL_TEXTS` 80-84, `partnerView` 358-374 (note line 373).
- `ci/mock/scenarios/B/partner-notice-draft.json`: `match.prompt` is the first `SYSTEMNOTE` sentence.

Contended, minimal hooks only (listed for the gate):
- `src/ocutalon/cls/OcuTalon/Watch/IncidentManager.cls`:
  - `AskedDraft` 1148: `For(incident.Production)` becomes `For(incident.Production, incident.Namespace)`.
  - `Drafted` 1304-1305: the same reader, and `"to"` becomes `Ids(contacts)`.
  - `RaiseAsked` after 1190 (`Set dryRun = {}.%FromJSON(result.DryRun)`): add one line, `Set dryRun = ##class(OcuTalon.Fix.Kind).Shown(kind, incident, dryRun)`.
  - 1203: `AskedKey(kind)` becomes `AskedKey(kind, dryRun)`.
  - `StoredDryRun` 1347-1360 and `RaiseFix` 1047-1062 stay unchanged.
- `src/ocutalon/cls/OcuTalon/Watch/Notice.cls`:
  - doc 49-52;
  - `KEYPARTNERREQUEST` 144: add `KEYPARTNERKEPTREQUEST`;
  - `AskedKey` 224-227: add the optional `dryRun`; `partner_warning` with `simulated` not 1 gives the kept key;
  - `AskedSlots` 244-258: add a branch for the kept key, `{production, notice}`.
- `src/ocutalon/cls/OcuTalon/Fix/Executor.cls` 823 (`ActionTarget`): add " (simulated)" only when `Fix.PartnerContacts.Simulated(incident.Production)`. Ready-first ordering is at 431-445, so a kept request never reaches `Deliver` 518-552. No other change.

Read-only evidence:
- `src/ocutalon/cls/OcuTalon/Data/PartnerContact.cls`: `ForProduction` 79-93 matches both namespace and production and gives rows in ID order.
- `Core/SettingsOps.cls` 2823-2832: `PartnersShown` is 1 only for `TABLE` exactly 1. `Values` 1007 leaves the member out on the online demo.
- `Live/Payload/Approval.cls` 127-136 builds "Name <address>" from the stored row and stays unchanged.
- `Data/Incident.cls` 15: `Namespace` is set at `IncidentManager` 445.
- `Watch/Reader.cls` 181-184: `OnlineDemo()`.
- `Demo/Guide.cls` 192-200: `DemoOn()`, a 60 s per-process cache.
- `bridge/.../Data/ApprovalRequest.cls` 11: `DRYRUNKEYS` already holds `recipients` and `simulated`.

Tests:
- `src/ocutalon/cls/OcuTalon/Test/Fix/PartnerWarning.cls` (warm, demo on in `OnBeforeOneTest` 71-79, `ZZNS` incidents at 465, the `Request` helper 484-488). Pins that move:
  - `TestContract` 109: `SYSTEMNOTE`;
  - `TestFacts` 121;
  - `TestParametersAndDryRun` 150 and 162-164;
  - `TestNoContacts` 183-202: the method list;
  - `TestRecheck` 205-226;
  - `TestTamperedRowSendsNothing` 341-348.
- `src/ocutalon/cls/OcuTalon/Test/Fix/PartnerDraft.cls` (shadow probe). Pins at 143, 175-191 and 606-609.
- `src/ocutalon/cls/OcuTalon/Test/Fix/PartnerTurns.cls` (fresh). Pins at 74-76 and 95. The `ResolvedIncident` 261-273 helper passes `..Fixture(session, ids, namespace, production, ...)` (`Test/Watch/Case.cls` 932), so it takes a production argument for a Settings-contact incident.
- `src/ocutalon/cls/OcuTalon/Test/Msg/Catalog.cls` 80-92 (key counts), 506 (the " Approve?" form), 523-533 (the key lists).
- `src/ocutalon/cls/OcuTalon/Test/Channel/TelegramApproval.cls` (press texts).
- `web/scripts/approval-view.test.mjs` 316-324.
- `web/e2e/settings/partner-contacts.spec.ts` 10-13 and 58-75: the GET simulation route.
- `web/e2e/support/partner-contacts.ts` 45-60: `partnerShown`, `realTable`.
- `src/ocutalon/cls/OcuTalon/Test/Core/SettingsPartners.cls` 331-348 already follows the real `TABLE`.

## Tasks & Acceptance

**Execution:**
- [ ] `src/ocutalon/cls/OcuTalon/Fix/PartnerContacts.cls` (DW-1393: de-duplication by address):
  - Add `Parameter TABLE = 1;`.
  - `Simulated(production)`: 1 when the fixture names the production.
  - `For(production, namespace = "")`:
    - a fixture production gives the fixture while `DemoOn()`, else [];
    - the online demo gives [] without reading the table;
    - otherwise `Data.PartnerContact.ForProduction(namespace, production)`, de-duplicated by lower-cased trimmed address, keeping the first in ID order (DW-1393).
  - `Named(production, id, namespace = "")` resolves through `For`.
  - `Ids(contacts)` reuses `Joined`.
  - Rewrite the class doc: no longer "demo-only, no table".
  - Keep it abstract, with no write method.
- [ ] `src/ocutalon/cls/OcuTalon/Fix/Kind.cls`: add `ForApprover(incident, dryRun)` (default: unchanged) and the `Shown(kind, incident, dryRun)` dispatcher. Name in the doc that it runs in the production job and its result is stored, never traced.
- [ ] `src/ocutalon/cls/OcuTalon/Fix/Kind/PartnerWarning.cls`:
  - `Facts` drops the Partner line.
  - `SYSTEMNOTE`'s first sentence becomes "Write a short delay notice to a partner about the failures described below." The rest is unchanged.
  - `CheckParameters`: `to` is ids.
  - `DryRun`:
    - reads `For(incident.Production, incident.Namespace)`;
    - `to` must equal `Ids`;
    - the targets are the ids;
    - the result is `{"notice", "recipients": [ids], "simulated": Simulated(production)}`.
  - `ForApprover` swaps the ids for `{id, name, address}` and drops an id that no longer resolves.
  - `Ready`: 1 only for a fixture production while demo mode is on, else `NOTSETUP`.
  - `Plan`:
    - Settings-contact targets are always skipped with `NOSTART` (no name);
    - fixture targets keep today's rule, matched by id at its position in `to`.
  - Update the class doc.
- [ ] `src/ocutalon/cls/OcuTalon/Watch/IncidentManager.cls`: the four hooks of the Code Map, and nothing else.
- [ ] `src/ocutalon/cls/OcuTalon/Watch/Notice.cls`: the kept key and slots of the Code Map, and the doc line. `AskedSlots` resolves its key with `AskedKey(kind, dryRun)`. Then search `src/` for every list of the approval-request key family that holds `incident.partnerRequest` (for example Telegram Out's request-key handling and `Test.Msg.Catalog` 523), and add `incident.partnerRequestKept` beside it.
- [ ] `src/ocutalon/cls/OcuTalon/Fix/Executor.cls` 823: the conditional " (simulated)". Update doc line 70.
- [ ] `src/ocutalon/cls/OcuTalon/Msg/Catalog/Watch.cls`: append `incident.partnerRequestKept`, with the texts of `### For the Planner's gate` (b), slots `production` (text) and `notice` (text).
- [ ] `src/ocutalon/cls/OcuTalon/Msg/Catalog/Core.cls`: append `press.approvedPartnerKept`.
- [ ] `src/ocutalon/cls/OcuTalon/Channel/Telegram/In.cls`: carry `simulated` in the slots for `partner_warning`. `PressText` gives `press.approvedPartnerKept` when it is 0.
- [ ] `web/src/app/approvals/approval-view.ts`: add `partnerKeptNote`; the pending note is chosen by `simulated`. Update the doc.
- [ ] `ci/mock/scenarios/B/partner-notice-draft.json`: the new first sentence as `match.prompt`.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Fix/PartnerWarning.cls`:
  - Update the moved pins: the method list, `SYSTEMNOTE`, the Facts (no "Partner:"), `to` as ids, recipients as ids and the tampered case.
  - Add tests with `zzpc` rows on `ZZNS`/`ZZPROD` for these matrix rows: SETTINGS_HAPPY at the kind level, DEDUPE (DW-1393), OTHER_SCOPE, NO_CONTACTS, EXECUTE_GUARD, DEMO_FIXTURE with a table row for Orders, ONLINE_DEMO_TABLE and KEPT (`Ready`).
  - Add a literal pin (DW-1394): `$Parameter("OcuTalon.Fix.PartnerContacts","TABLE")` = "1" and `SettingsOps.PartnersShown()` = 1.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Fix/PartnerDraft.cls`:
  - Update 143 and 175-191 (`to` = "1", recipients [1] in the answer, slots from the resolved row).
  - Add a Settings-contact draft: the Decide input and the `DryRun`/`Notification` messages captured by the probe hold neither the name nor the address; the key is `incident.partnerRequestKept`; the row's `DryRun` holds both.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Fix/PartnerTurns.cls`:
  - Update 74-76 (ids).
  - Add `TestSettingsContactsLeakNothing`:
    - a resolved incident on `ZZPROD` in `OCUORDERS`, and two `zzpc` contacts with unique names and addresses, one a duplicate address;
    - the asked turn raises one request with one id per address;
    - approve it, and it is kept (`result.partnerKept`, no mail);
    - then scan for each name and address: `TraceLeaks` "", no audit entry, no `Ens_Util.Log` text, and `Leaks` exactly the contact row's global, the approval row's global and the live-event global (DW-1254, DW-1394 "only after approval").
- [ ] `src/ocutalon/cls/OcuTalon/Test/Msg/Catalog.cls`: counts +1 Watch and +1 Core; add the new key to the request-key lists and the " Approve?" form.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Channel/TelegramApproval.cls`: the press key for a simulated-0 row.
- [ ] `web/scripts/approval-view.test.mjs`: the kept note for `simulated` false, the old note for true, and `partnerKeptNote` in the key loop.
- [ ] `web/e2e/settings/partner-contacts.spec.ts` (DW-1394):
  - drop the `beforeEach` GET route 58-75 and rewrite the header 10-13;
  - P1 asserts `realTable()` is "1", `partnerShown` is true, and both halves of `settings.partnersHelp` are visible on the real page;
  - keep the per-test POST stubs.
- [ ] Search the test trees for the old shapes (`it@orders-partner.example` in `to`, `"to": "<address>"` partner rows, "Partner: Orders Partner IT", "named below") and update each one that the kind re-validates.

**Acceptance Criteria:**
- **AC1 (TABLE, DW-1394).** Given the compiled class, when an admin of a non-online-demo install loads Settings, then `TABLE` is 1, `GET /api/v1/settings` carries `partner-contacts`, and Settings › Partner contacts shows after On call with both halves of `settings.partnersHelp`. On the online demo the member is still absent and the route still answers 409.
- **AC2 (only the listed contacts).** Given a warning for an incident of a watched production that is not the demo's, when it is raised, then its recipients are exactly that production's Settings contacts (namespace and production, de-duplicated by address), and nothing else is ever a recipient.
- **AC3 (ids, DW-1254).** Given a Settings-contact warning's whole lifecycle (ask, draft, raise, approve, kept), when the trace bodies, the event log, the audit log and the `^OcuTalon*` globals are scanned, then no trace, log or audit entry holds a contact's name or address. Only the contact row, the approval row and the approval live event hold them.
- **AC4 (the approver sees exact recipients).** Given a raised Settings-contact request, when the approver opens the card, then it shows every recipient as "Name <address>" and the exact notice. The chat or Telegram request text (`incident.partnerRequestKept`) names none of them.
- **AC5 (only after approval, never sent yet).** Given a Settings-contact request, when it is approved, then nothing is delivered anywhere, including the Simulated mailbox, the row keeps the text, and the user reads `result.partnerKept`. Before approval nothing happens, and `Execute` with no approved row does nothing.
- **AC6 (the demo is unchanged).** Given the Orders production with demo mode on, when "Warn the partner" runs, then 23.5's flow, its texts and its Simulated-mailbox send are unchanged. The draft's facts no longer name the partner.
- **AC7 (integration: consumers).** Given `TABLE = 1`, then `SettingsOps.PartnersShown()` (consumer: the Settings page) shows the section, and `IncidentManager` (consumer: the reader) raises a request whose targets are the listed contacts' ids.

## Spec Change Log

- 2026-11-15 ~23:35Z (lead, Planner 23.13 GATE): veto 2 changed (send through 21.11 EmailOut when a mailbox is connected; kept only when none); intent block amended; status reset to draft for a re-plan of the changed part.

## Review Triage Log

## Design Notes

**Governing ADs (Rule 6):**
- AD-16 (fixed kinds, the dry run stored in the row, the executor trusts the row; `partner_warning` parameters `text` and `to`);
- AD-15 (`IncidentManager` the only writer, drafting through Draft/Decide);
- AD-11 (the row is the truth);
- AD-12 (the approval payload's `Notice`/`Recipients`/`Simulated`, no new field);
- AD-14 (the simulated partner notice in SimMailbox);
- AD-17 (the audit holds ids, no identities);
- AD-19 (partner contacts' fixed homes, the `TABLE` switch, the partner audit exception);
- AD-13 (no direct reads of product storage from the web process: the ids are resolved in the production job, so the card's read path is unchanged);
- AD-24 (personal data never in a traced message);
- AD-25 (the online demo);
- AD-29 (lanes, and `ForProduction` as the cross-lane reader);
- AD-32 (producers never render; new keys are catalog keys);
- AD-33 (one owner per table: `SettingsOps` writes, Lane A only reads).

**Decided in-stage:**
- **Source by production, not by demo mode.** An incident's production never changes, so a request's ids always resolve against the same source, even if demo mode is toggled between the raise and the approval. A fixture id can never be read as a table row ID.
- **Settings contacts are kept, not simulated, even with demo mode on.** No `PartnerNotice` or `SimMessage` row ever holds a real contact. This is the only reading under which "never sent to anyone else" holds until EmailOut delivers by id.
- **Ids go in the traced messages; the production job resolves names into the stored row.** This is the DW-1255 precedent: the row is the truth (AD-11, AD-16), and neither the card nor the web process reads the table.
- **Facts drop the partner line for both sources.** One invariant: the model never sees a contact.
- **De-duplication.** Compare lower-cased, trimmed addresses and keep the lowest id. `MailAllowed` counts the de-duplicated list.

**Extend, don't copy (Rule 2):**
- `For`/`Named` extend the fixture reader in place, through the same `{id, name, address}` shape as `ForProduction`.
- `Ids` reuses `Joined`.
- `ForApprover` follows the per-kind hook pattern of `Ready`/`Facts`, dispatched like `ForName`.
- The kept key copies `incident.partnerRequest`'s structure.
- The leak scan reuses the 24.2 helpers rather than copying `Scan`.

**Consumes:** `Data.PartnerContact.ForProduction` (Story 24.2); `SettingsOps.PartnersShown` reads `TABLE` (24.2).
**Consumed-by:**
- Story 24.4 (the cards show partner warnings: the recipients through this reader and the stored row);
- the Epic 21 EmailOut follow-up (delivers Settings-contact requests by id, read from the row at send time, and replaces `Ready`'s `NOTSETUP` and `Plan`'s `NOSTART` guard).

**Ledger inbox (Rule 17):**
- DW-1393 is addressed (Tasks: `PartnerContacts` de-duplication; matrix DEDUPE).
- DW-1394 is addressed (AC1, AC5; the literal pin and the real e2e state).
- DW-1254's contact-id part is AC3. The ledger entry stays 24.2's.

### Planner rulings, 23.13 GATE (2026-11-15 ~23:30Z; BINDING; prompts/story-242-rulings-20261115.md "23.13 GATE")
- APPROVED with ONE CHANGE (veto 2): the send rule in the intent block above (SENT through 21.11's EmailOut when a mailbox is connected; kept as an approved draft ONLY when none is connected; STOP if EmailOut can't carry it).
- Public text APPROVED with conditional wording, verbatim:
  - Phone and web forms of `incident.partnerRequestKept`, the Dry run line: "Dry run: no mailbox is connected in Settings > Channels > Email, so if you approve, the notice is kept as an approved draft and nothing is sent." The rest of the two forms verbatim as proposed.
  - `press.approvedPartnerKept`: "Approved. The delay notice is kept as a draft: no mailbox is connected in Settings > Channels > Email."
  - `APPROVAL_TEXTS.partnerKeptNote`: "Nothing is sent unless you approve. No mailbox is connected in Settings > Channels > Email, so an approved notice is kept as a draft."
  - SENT path: reuse 21.11's approved email texts where they fit; any new line goes to the Planner.
- Vetoes 1, 3, 4 APPROVED (online demo unchanged; trace, logs and audit carry contact ids only; the approval row holds names and addresses until the standard purge). Deviations 1-5 ACCEPTED. The AD-16 bullet (written by the lead with the Planner's marker) includes the sent-or-kept rule.
- Contention: plain union with lane D's 24.4a (`Live/Payload/Incident.cls`, `Watch/IncidentManager.cls`, `Fix/Executor.cls`).

### For the Planner's gate

**(a) Veto items, each with its online-demo behaviour:**
1. **To whom a warning goes.**
   - The demo production keeps the fictional fixture while demo mode is on.
   - Every other production goes to its Settings contacts, de-duplicated.
   - The table is never read on the online demo.
   - Online demo: unchanged (fixture, simulated, Simulated mailbox); the Settings section is still hidden and its route still answers 409.
2. **What a Settings-contact warning sends.** Nothing, in any mode: it is kept as an approved draft until EmailOut. Online demo: not reachable (there are no Settings contacts there).
3. **Stored data.**
   - `to` in `FixParameters` changes from addresses to contact ids.
   - The approval row's `DryRun` and the approval live event hold the Settings contacts' names and addresses for the approver. They are purged by the standard retention and outlive a removed contact until then.
   - Traces, logs and audit hold ids only.
   - Online demo: fixture rows only, as today.
4. **`TABLE = 1`** shows Settings › Partner contacts on every install that is not the online demo. Online demo: unchanged (hidden by `SettingsOps`).

No privilege, role or route changes.

**(b) Public text:**
- **NEW** `incident.partnerRequestKept` in `Msg/Catalog/Watch.cls`:
  - text: "I drafted a delay notice about this incident for the partner contacts set for {production}. Approve?\n\nDry run: email delivery isn't set up yet, so if you approve, the notice is kept as an approved draft and nothing is sent. The recipients are on the approval card on your OcuTalon page.\n\n{notice}\n\nNothing has been sent yet.\n\nDetails and trace: on your OcuTalon page."
  - web: "I drafted a delay notice about this incident for the partner contacts set for {production}.\n\nDry run: email delivery isn't set up yet, so if you approve, the notice is kept as an approved draft and nothing is sent.\n\n{notice}\n\nNothing has been sent yet.\n\nDetails and trace: on your OcuTalon page."
- **NEW** `press.approvedPartnerKept` in `Msg/Catalog/Core.cls`: "Approved. The delay notice is kept as a draft: email delivery isn't set up yet."
- **NEW** `APPROVAL_TEXTS.partnerKeptNote` in `web/src/app/approvals/approval-view.ts`: "Nothing is sent unless you approve. Email delivery isn't set up yet, so an approved notice is kept as a draft."
- **Approved and reused unchanged:** Story 23.5's partner keys (`incident.partnerRequest`, `result.partner*`, `summary.*Partner*`, `partner.subject`, `press.approvedPartner`, the card's `partnerTo`/`partnerNote`/`partnerKept`), the 23.10 contact name, and 24.2's `settings.partnersHelp`, `settings.partnersOffOnDemo` and `settings.partnerRemoveConfirm`.
- **Not public:** the `SYSTEMNOTE` sentence and the mock B prompt.

**(c) Contended-file overlaps (plain union, minimal):**
- `Watch/IncidentManager.cls`: 4 one-line hooks (Lane D 24.4a).
- `Watch/Notice.cls`: the `AskedKey` optional argument, one `AskedSlots` branch and one parameter.
- `Fix/Executor.cls` 823: 1 line (Lane D 24.4a).
- `web/e2e/settings/partner-contacts.spec.ts`: 24.2's test, in the Settings area that Lane C works in. The simulation route is dropped.

**(d) Deviations, with recommendations:**
1. Settings contacts are not delivered to the Simulated mailbox even with demo mode on (23.5's `Ready` would). Recommend accept: it keeps real people out of `PartnerNotice` and `SimMessage`.
2. `PartnerNotice` still carries "Name <address>" in its subject slot, but only for the fictional fixture contact, the only one ever delivered. The Planner's DW-1254 note lists `PartnerNotice` ids. Recommend the EmailOut follow-up carry ids (the DW-1255 pattern).
3. The demo's traced `incident.partnerRequest` still names the fictional contact (approved text, no personal data). Recommend accept.
4. The charter says "after 23.4 and 23.8", and 23.8 is parked. 23.13 shares no file with 23.8 (inference). The lead's dispatch ruling.
5. Recommend that the lead add an AD-16 bullet recording the source rule and the kept rule (Rule 20; an AD amendment is a veto item).

**(e) CI:**
- No `.github/workflows` or `release/**` hunk, and no new unit or group.
- The tests are new methods in existing classes:
  - `shard:lane-a@Fix` (shards-11): `PartnerTurns` adds about 40-60 s (inference);
  - `lane-b` Core/Msg/Channel;
  - the `web` job;
  - `live:sign-in-2` for `e2e/settings`.

## Verification

Run from the epic-23 worktree root, one command per call with `timeout: 600000`, each sized to about 150 s, and never two test runs in one message.
- Prefix every `ci/` call with `OCUTALON_LOCK_DIR=<main checkout>/.worktrees/.coordination/locks/lane-b OCUTALON_TEST_WEB_PORT=52802 OCUTALON_LOCK_OWNER='epic=23 stage=implement'`.
- Tags: fresh `e23b13i`, warm `e23b13iw`.
- Change `ci/mock/**` before `ci/warm.sh up`.
- At the end, also after a failure, run `ci/warm.sh down`, then `ci/iris.sh teardown` with each tag.

**Shared surfaces:**
- the partner-warning recipients and the `to`/dry-run shape (the `Request` helpers and the row fixtures in `Test.Demo.Guide`, `Test.Eval.Report`, `Test.Live.Payloads`, `Test.Channel.TelegramApproval` and `Test.Fix.Kind`);
- the Settings sections shown (`partner-contacts` is now present off the online demo: S1/S1f, deep-link, on-call, roles and `Test.Core.SettingsSave` 441 follow the real value);
- the leak-scan inputs;
- the catalog key counts and request-key lists (`Test.Msg.Catalog`);
- `APPROVAL_TEXTS` keys;
- `SYSTEMNOTE` and the mock B prompt;
- the `Fix.PartnerContacts` method list.

Every test added or changed passes on a fresh environment, in either order.

**Commands:**
- (loop) `OCUTALON_RUN_TAG=e23b13iw ci/warm.sh up`; re-up (down, then up) after any change to `ci/mock/**` or the production's Fix and Watch classes. Then `OCUTALON_WARM=1 OCUTALON_RUN_TAG=e23b13iw ci/iris.sh class <C>`, one call each, for these classes. Expected: `CLASS ... passed`.
  - `OcuTalon.Test.Fix.PartnerWarning`
  - `OcuTalon.Test.Fix.PartnerDraft`
  - `OcuTalon.Test.Msg.Catalog`
  - `OcuTalon.Test.Channel.TelegramApproval`
  - `OcuTalon.Test.Fix.PartnerTurns:TestSettingsContactsLeakNothing`
  - `OcuTalon.Test.Fix.PartnerTurns:TestAskedTurnRaisesWithinBounds`
- (loop) `node --test web/scripts/approval-view.test.mjs` -- expected: pass.
- (loop) `bash docker/tests/test-mock.sh` -- expected: pass.
- (once) On the warm stack, one call each: `OcuTalon.Test.Fix.PartnerTurns` methods `TestApprovedNoticeIsSentByteForByte`, `TestDemoModeOffKeepsTheNotice`, `TestInjectedTurn`, `TestSecondSessionAsks` and `TestResolvedDraftSaysTheOrdersWentThrough`; then the classes `OcuTalon.Test.Core.SettingsPartners`, `OcuTalon.Test.Core.SettingsSave`, `OcuTalon.Test.Web.PartnerSettingsApi`, `OcuTalon.Test.Live.Payloads`, `OcuTalon.Test.Fix.Kind`, `OcuTalon.Test.Demo.Guide` and `OcuTalon.Test.Eval.Report`. Expected: passed.
- (once) `OCUTALON_RUN_TAG=e23b13i ci/iris.sh class OcuTalon.Test.Fix.PartnerTurns:TestSettingsContactsLeakNothing` on a fresh stack -- expected: passed.
- (once) `npm --prefix web test` -- expected: pass.
- (once) `OCUTALON_RUN_TAG=e23b13i ci/iris.sh build`, then `OCUTALON_RUN_TAG=e23b13i ci/iris.sh live sign-in-2 --part k/N` for the part that holds `settings/partner-contacts.spec.ts`. Find k/N with `npm --silent --prefix web run e2e:sign-in-2 -- --list --reporter=json` and `node web/scripts/e2e-part.mjs`, choosing N so that the part ends inside about 150 s. Expected: passed.
- (once) Each script of `CHECK_SCRIPTS` in `ci/units.sh` as `bash docker/tests/test-<name>.sh`, one per call -- expected: each passes.
- Left to CI: the shards (`lane-a@Fix` in shards-11, lane-b), the other browser units, and the lead's fresh-environment check, forward and `--reverse`.

**Mutations (Rule 19), one per AC, each recorded as `mutation: <change> -> <test red>`:**
- AC1: remove `TABLE` -> the PartnerWarning literal pin, and e2e P1.
- AC2: drop the namespace match or the de-duplication in `For` -> PartnerWarning DEDUPE/OTHER_SCOPE.
- AC3: put the name back into `Facts`, or names into the dry run -> `PartnerTurns:TestSettingsContactsLeakNothing`.
- AC4: `ForApprover` returns the ids unchanged -> PartnerDraft's row/card assertion.
- AC5: `Ready` gives 1 for a Settings production with demo mode on -> PartnerWarning KEPT.
- AC6: `Simulated` gives 0 for the Orders production -> `PartnerTurns:TestApprovedNoticeIsSentByteForByte`.
- AC7: `IncidentManager` keeps `For(incident.Production)` with no namespace -> `PartnerTurns:TestSettingsContactsLeakNothing` (no request).

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
