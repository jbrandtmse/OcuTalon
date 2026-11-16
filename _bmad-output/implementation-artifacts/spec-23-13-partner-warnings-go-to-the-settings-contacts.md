---
title: 'Story 23.13: Partner warnings go to the Settings contacts'
type: 'feature'
created: '2026-11-15'
status: 'in-progress'
baseline_revision: 'dbc68f1d4a7fbd46a547558c66f290808a9b93ce'
baseline_commit: 'dbc68f1d4a7fbd46a547558c66f290808a9b93ce'
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
- **[AMENDED 2026-11-15, Contest Planner 23.13 GATE ruling (prompts/story-242-rulings-20261115.md "23.13 GATE"), veto 2 CHANGED; BINDING]** An approved partner warning to Settings contacts is SENT through Story 21.11's EmailOut path, from the mailbox connected in Settings > Channels > Email: one approval, sent exactly once. It is kept as an approved draft ONLY when no mailbox is connected, and its texts then say so truthfully. If the EmailOut path CAN'T carry it, STOP: name the file and line and say why, before building a kept-draft-only version (HALT `blocked`, `intent gap`). **[AMENDED 2026-11-15 ~23:55Z, Contest Planner "23.13 EmailOut" ruling (option (i)); BINDING]** EmailOut CAN carry it after this story's own change: 23.13 edits Lane B's `Channel/Email/Out.cls` (`Authorised`, `ApprovedRecipients`, `Approved`) under the approved AD-14 amendment (EmailOut's system send accepts any executing fix request whose `Fix.Kind` provides a new mail method; for kind `email` it returns today's values), and adds the `Fix/Executor.cls` branch (plain union with Lane D's 24.4a). SECURITY CONDITION (approved-address rule): a message goes ONLY to an address the approver saw on the approval card (stored in the approval row). At send time resolve the contact ids; send to an address only if that contact still exists AND its address equals the one stored at approval; a removed contact or a changed address is SKIPPED and reported in the result, never sent to the new address; if every recipient is skipped nothing is sent and the result says so. Pins: same address sent; removed contact skipped; changed address skipped; the online-demo refusal for `partner_warning`. One send per approval (claim, lock, Delivery row) and count-only logs carry over unchanged. Texts: the sent result reuses `fix.emailSent` / `fix.emailNotSent`; the no-mailbox request uses `incident.partnerRequestKept` as ruled; TWO NEW lines (the mailbox-connected request, and the skipped-recipient result line) are drafted in this spec under PUBLIC TEXT and go to the Planner before those two surfaces are implemented. Texts: the kept path uses the Planner's conditional wording verbatim (see Design Notes "Planner rulings, 23.13 GATE"); the SENT path reuses 21.11's approved email texts where they fit; ANY new line is NEW public text for the Planner (list it under the gate, verbatim). The online demo is unchanged (no Settings contacts, nothing sent; fictional contact to the Simulated mailbox).

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
- **[RE-PLANNED 2026-11-15 under the two binding amendments above] Settings-contact requests (simulated 0): sent or kept.**
  - The request's chat key is chosen when it is raised: `incident.partnerRequestMailbox` (NEW, gated) when a mailbox is connected, else `incident.partnerRequestKept` (ruled). Both have slots `production` and `notice` and name no recipient.
  - `Ready` is 1 only when a mailbox is connected (`email.address` is an address) and the online demo is off; else 0 with `NOTSETUP`, and the approved notice is kept (`result.partnerKept`).
  - When ready, the executor never calls `Recheck`/`Execute`/`Deliver` for them (no `PartnerNotice`, no Simulated mailbox copy). It asks the kind's mail method for the sendable addresses under the approved-address rule, and submits ONE `SendEmail` with origin `system`, the request's `ApprovalRef` and nothing else (no address, subject or text in the command or the trace), exactly as `Fix.Kind.Email` does.
  - **The mail method (AD-14 amended).** `Fix.Kind` gains `MAILS` (0) and `Mail(row, .recipients, .subject, .text, .skipped)`; `Fix.Kind.Mailed(row, ...)` dispatches only for a row of Kind `fix`, State `executing`, a registered kind with `MAILS` 1. `Fix.Kind.Email.Mail` returns today's values from `FixParameters` (recipients only when every entry is a string; subject and text "" when the member is not a string). `Fix.Kind.PartnerWarning.Mail` gives 0 for a fixture production (a fictional contact is never mailed), else: text = `FixParameters.text` only if it equals the stored `DryRun.notice`; for each id of `to`, the address stored for that id in the row's `DryRun.recipients` is sent to only when `For(production, namespace)` still holds that id with exactly that address (trimmed, case-sensitive); else the id is skipped with code `removed` (gone, or no longer listed for that production, or no stored address) or `changed`, reason `NOSTART`.
  - `Channel.Email.Out` `Approved`, `ApprovedRecipients` and `Authorised` read the row through `Fix.Kind.Mailed` instead of `FIXKIND`/`FixParameters`; every other step of `Handle` (online-demo refusal first, `not_connected`, `Check`, the claim by `ApprovalRef` under the lock with its `Data.Delivery` row, count-only logs) is unchanged and applies to `partner_warning`.
  - Results: all recipients sent: `fix.emailSent`; some or all skipped: `result.partnerSkipped` (NEW, gated; counts only); send refused or failed with one of Out's sentences: `fix.emailNotSent` {reason}; any other failure: `result.partnerNotSent` {reason}; kept: `result.partnerKept`.
  - The Action audit target drops " (simulated)" for them.
- **Other text for Settings-contact requests.** The Telegram press reads `press.approvedPartnerKept` when no mailbox is connected and gives no text when one is (the existing empty-answer path). The web card has no pending note for them, and its result bands follow the result keys above.
- Reuse the 24.2 leak-scan helpers (`Test.Core.SecretHandoff.Leaks` and `TraceLeaks`, `Test.Bridge.AuditLog.Entries`, `Test.Web.WebhookTools.LogText`).
- In every added test, create and remove its own contact rows (Name prefix `zzpc`, `%DeleteId` in `OnAfterOneTest`).

**Never:**
- Edit Lane B's contracts other than the three ruled methods of `Channel/Email/Out.cls` (and its class doc): `Data.PartnerContact`, `Core/SettingsOps.cls`, `Web/PartnerSettings.cls`, `Web/Api.cls`, `web/src/app/settings/**`.
- Read the table on the online demo, or from the web process.
- [RE-PLANNED] Send to a Settings contact through any channel but EmailOut's claimed system send of its approved row, or to any address the approval row does not hold for that id; deliver a Settings contact to the Simulated mailbox; mail a fixture (simulated) contact for real.
- Put a Settings contact's name or address into a traced message (Draft/Decide input, `DryRun`, `DryRunResult`, `Notification`, `FixResult`, `PartnerNotice`, `SendEmail`, `CommandResult`), a log line, an audit entry or `FixRun.Reason`.
- Change the demo's approved texts or its "Warn the partner" flow.
- Touch `Fix/Executor.cls`, `Watch/IncidentManager.cls`, `Watch/Notice.cls` or `Watch/Summary.cls` beyond the hooks listed in the Tasks.
- Implement the two NEW lines' surfaces, or the email subject, before the Planner's ruling (see `### For the Planner's gate`).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| SETTINGS_HAPPY | Local install; production `ZZPROD` (namespace `ZZNS`) has Settings contacts A (id a) and B (id b); a warning is asked | The request has `to` = targets = "a,b" and a dry run with `recipients` [a, b] and `simulated` 0. The row `DryRun` holds `[{a, nameA, addrA}, {b, ...}]`. The card shows "To: nameA <addrA>, nameB <addrB>". The Notification key is `incident.partnerRequestMailbox` (mailbox connected) or `incident.partnerRequestKept` (none), with no name. | none |
| DEDUPE (DW-1393) | Contacts 3 and 5 both list `ZZPROD`, with addresses `X@Y.example` and ` x@y.example` | One recipient, id 3, and targets "3" | none |
| OTHER_SCOPE | A contact lists `ZZPROD` under another namespace, or another production | Not a recipient | none |
| NO_CONTACTS | `ZZPROD` has no Settings contact | `AskedDraft` refuses with `NOCONTACTS`; nothing is drafted or raised | refusal text |
| SENT | Mailbox connected; the SETTINGS_HAPPY request is approved; A and B unchanged | One email from `email.address` to exactly addrA and addrB, the approved notice byte for byte, one `Data.Delivery` row (channel email, the approval's Ref); run done, Completed 2; the session reads `fix.emailSent`; the card band is `fix.emailSent` | none |
| KEPT | No mailbox connected (demo mode on or off) when it is approved | Could not start with `NOTSETUP`; no `SendEmail`, no mail, no `PartnerNotice`; `result.partnerKept`; Telegram press `press.approvedPartnerKept`; the Action target is "2 partner contacts (a,b) of ZZPROD" | none |
| SKIPPED_REMOVED | As SENT, but contact b was deleted (or unlinked from `ZZPROD`) after the request was raised | Email to addrA only; b skipped (code `removed`); run done, Completed 1, Skipped 1; `result.partnerSkipped` {sent 1, skipped 1, total 2} | none |
| SKIPPED_CHANGED | As SENT, but b's address was changed to addrB2 after the request was raised | Email to addrA only; nothing ever goes to addrB2 or addrB; b skipped (code `changed`); `result.partnerSkipped` | none |
| ALL_SKIPPED | Both contacts removed or changed | No `SendEmail` is submitted and nothing is sent; run done, Completed 0, Skipped 2; `result.partnerSkipped` {sent 0, skipped 2, total 2} | none |
| SEND_FAILED | Mailbox connected at `Ready`, but Out answers `not_connected`, `failed` or `refused` | Run failed with Out's sentence as the reason; `fix.emailNotSent` {reason}; Out keeps its claim marked failed, so the approval never sends | none |
| ONE_SEND_PER_APPROVAL | A second `SendEmail` (origin system) for the same partner approval reaches Out | `already_sent` (after a sent one) or `failed` (after a failed one); nothing is sent again; still one Delivery row | none |
| DEMO_REFUSED | The online-demo flag is on and an executing `partner_warning` row is submitted to Out | `not_available` (MESSAGEUNAVAILABLE); nothing delivered, no claim row | none |
| FIXTURE_NOT_MAILED | An executing `partner_warning` row of the Orders production is submitted to Out | `refused` (recipients); nothing sent: a fictional contact is never mailed | none |
| EMAIL_UNCHANGED | Story 22.7 `email` rows, every case of `Test.Channel.EmailOut` and `Test.Fix.Email` | Unchanged outcomes | none |
| EXECUTE_GUARD | `Recheck`/`Execute` are called directly on a Settings-contact request | `deliveries` []; each target skipped with `NOSTART` | none |
| DEMO_FIXTURE | The Orders production with demo mode on (local or online demo), even with a Settings contact listing it | As in 23.5: contact 1 "Orders Partner IT", `simulated` 1, `incident.partnerRequest` naming it, Simulated mailbox after approval byte for byte, `press.approvedPartner`, the card's Simulated texts | none |
| DEMO_OFF | The Orders production with demo mode off | `NOCONTACTS`; nothing is drafted | refusal text |
| ONLINE_DEMO_TABLE | The online-demo flag is on; a table row (written directly) lists `ZZPROD` | `For` gives []; the table is not read | `NOCONTACTS` |
| TAMPERED | A row whose `to` is an address, or ids that are not the targets, or whose text is not the stored notice | `CheckParameters`/`AsApproved`/`Mail` refuse; every target is `NOSTART`; nothing is sent | none |
| NO_APPROVAL | `Execute` with no approved row | Nothing is sent or kept beyond today's per-kind refusal | none |

</intent-contract>

## Code Map

All paths under `src/ocutalon/cls/OcuTalon/` unless they start with `web/`, `ci/` or `src/bridge/`.

Lane A (edit freely):
- `Fix/PartnerContacts.cls`: fixture XData 13-18; `For` 21-32 (demo-only), `Named` 35-43, `Addresses`/`Names`/`Joined` 46-66, `All` 69-86. Add `TABLE = 1`, `Simulated(production)`, the table branch, the de-duplication and `Ids` (reuses `Joined`).
- `Fix/Kind.cls`: doc 1-33; parameters 37-84 (`NOTSETUP` 78, `KINDS` 84); `ForName` 113; base `Ready` 261. Add `ForApprover`/`Shown` (the 23.13 approver hook) and `MAILS`/`Mail`/`Mailed` (the mail method).
- `Fix/Kind/Email.cls`: doc 1-17; `AsApproved` 182; `Execute` 197-211 (the Submit of a system `SendEmail` with only `ApprovalRef`, owner session); `Joined` 213. Add `Mail` (today's values) and `MAILS = 1`; extract Execute's body into public `SubmitApproved(row)`, which Execute and the executor's partner branch both call.
- `Fix/Kind/PartnerWarning.cls`: doc 1-14; `SYSTEMNOTE` 41; `NOTSETUP`/`NOCONTACTS`/`RECHECK`/`NOSTART` 43-57; `Facts` 61-83 (Partner line 71); `CheckParameters` 170-180, `AddressList` 183-189; `DryRun` 193-212; `Ready` 221-227; `Recheck`/`Execute`/`Plan` 231-278.
- `Fix/Executor.cls` (also Lane D 24.4a, plain union): doc 62-68 (contact branch) and 83-88 (email); `SendEmail` 286-331 is the sibling of the new partner send; `Run` 412-516, contact branch 431-444 and the end at 470-486; `Deliver` 518-554; `AsApproved` 556-566; `ActionTarget` contact line 824; `FirstReason` 877.
- `Msg/Catalog/Watch.cls` partner keys 960-1045 (`incident.partnerRequest` 960-968 is the shape to copy); `Msg/Catalog/Core.cls` `fix.emailSent`/`fix.emailNotSent` 690-699, `press.approvedPartner` 907-911.
- `Channel/Telegram/In.cls`: `FixSlots` 477-494, `PressText` 498-530 (partner branch 516-517).
- `web/src/app/approvals/approval-view.ts`: doc 30-33 and 563-566; `APPROVAL_TEXTS` 75-90 (partner 80-85); `partnerView` 358-375 (note 373); `resultView` 575 (partner route 586-587); `partnerResultView` 705-737.
- `web/src/app/approvals/approval-request-card.ts` 531-535 (the band; `this.shown().dryRun?.simulated` is available), 135-136 (Simulated label, unchanged).
- `web/src/app/incidents/incident-view.ts` 100 (`IncidentContext.result`), 454 (`bandsOf`), 503; `web/src/app/incidents/incident-card.ts` 34 and 296 (`approvals` input: the live store's payloads by Ref).
- `web/scripts/catalog.mjs`: `LISTED_KEYS` 67-132, `TEXT_SLOT_KEYS` 147-169; regenerate `web/src/app/msg/catalog.ts` with `npm --prefix web run catalog`.
- `ci/mock/scenarios/B/partner-notice-draft.json`: `match.prompt` is `SYSTEMNOTE`'s first sentence.

Lane B, ruled for this story (option (i)):
- `Channel/Email/Out.cls`: doc 11-24 (Listed, Approved, Authorised paragraphs); `FIXKIND`/`FIXRECIPIENTS` 73-76; `Handle` 167-190 (unchanged order); `Listed` 393-401; `Approved` 405-438; `ApprovedRecipients` 440-462; `Authorised` 505-547. Edit only the three methods and their doc lines; keep `FIXKIND` (read by `Core/BridgeSink.cls`, `Eval/Gate.cls` and `Test/Tools/Email.cls`), documented as Story 22.7's kind.

Contended, minimal hooks only (listed for the gate):
- `Watch/IncidentManager.cls`: `AskedDraft` 1148 `For(incident.Production)` -> `For(incident.Production, incident.Namespace)`; `Drafted` 1304-1305 the same reader and `"to"` -> `Ids(contacts)`; `RaiseAsked` after 1193 (`Set dryRun = ...`): one line `Set dryRun = ##class(OcuTalon.Fix.Kind).Shown(kind, incident, dryRun)`; 1204 `AskedKey(kind)` -> `AskedKey(kind, dryRun)`; `ResultNotice` 1714: pass `##class(OcuTalon.Fix.PartnerContacts).Simulated(incident.Production)` as `ResultKey`'s fourth argument. `StoredDryRun` 1347-1360 and `RaiseFix` 1047-1062 unchanged.
- `Watch/Notice.cls`: doc 49-52; keys 143-154; `AskedKey` 224-227; `AskedSlots` partner branch 243-257; `ResultKey` 404-422 (contact branch 408-413); `ResultSlots` partner block 446-454.
- `Watch/Summary.cls`: doc 13; `RunEvents` 190.

Read-only evidence:
- `Data/PartnerContact.cls` `ForProduction` 79-93 (namespace and production both match; ID order).
- `Core/SettingsOps.cls` 2823-2832 (`PartnersShown` is 1 only for `TABLE` exactly 1); `Values` 1007 drops the member on the online demo; `IsAddress`.
- `Live/Payload/Approval.cls` 127-136 builds "Name <address>" and `Simulated` from the row (unchanged); `Live/Payload/Part/DryRun.cls` 37-43.
- `src/bridge/cls/OcuTalon/Bridge/Data/ApprovalRequest.cls` 11 `DRYRUNKEYS` (unchanged).
- `Core/Commands.cls` 22-40 (`Submit` is synchronous through `CommandsIn`); `Core/BridgeSink.cls` 272-287, 367-379 (the email kind's result choice, private, not reused).
- `Watch/Reader.cls` 181-184 `OnlineDemo()`; `Demo/Guide.cls` 192-200 `DemoOn()`.

Tests (existing, to update or extend):
- `Test/Fix/PartnerWarning.cls` (warm; demo on in `OnBeforeOneTest` 71-79; `ZZNS` incidents 465; `Request` 484-488): pins that move `TestContract` 109, `TestFacts` 121, `TestParametersAndDryRun` 150/162-164, `TestNoContacts` 183-202 (method list), `TestRecheck` 205-226, `TestTamperedRowSendsNothing` 341-348.
- `Test/Fix/ExecutorProbe.cls`: `SendResult` 119, `SendNotice` 207, `WriteAudit` 218, `Carry` 307 (`CarryIs`). Add the override of the new mail seam.
- `Test/Channel/EmailOut.cls` (warm, no production): `Send` 1372 (shadow `EmailOutProbe`, `OnSendEmail`), `Approval` 1406 (row helper), `Mailbox` 1383, `Delivered` 1391, `Claims` 1452, `Reset` 1495, `OnBeforeAllTests`/`OnAfterAllTests` 82/99; `TestSystemApproval` 648, `TestOnlineDemo` 697, `TestNoDoubleSend` 792, `TestNoPersonalDataInTheLog` 1145. `Test/Channel/EmailOutProbe.cls` `Deliver` 21 records `("sent",n)` = $LB(from, to, subject, text, ...).
- `Test/Fix/Email.cls` (fresh only, real production + CI mock SMTP): `SmtpControl` 176, `SmtpState` 186, `Mails` 204, `EmailDeliveries` 224, `Connect` 233, `Disconnect` 271, `Seed` 424, `SendOutcome` 443; `TestSeededApprovedRowSendsOnce` 608 is the end-to-end template.
- `Test/Fix/PartnerDraft.cls` pins 143, 175-191, 606-609. `Test/Fix/PartnerTurns.cls` pins 74-76, 95; `ResolvedIncident` 261-273 (takes a production argument for a Settings-contact incident, `Test/Watch/Case.cls` 932).
- `Test/Msg/Catalog.cls` 80-92 (counts), 506 (" Approve?" form), 523-533 (request-key lists). `Test/Channel/TelegramApproval.cls` (press texts). `Test/Core/SettingsPartners.cls` 331-348 already follows the real `TABLE`.
- `web/scripts/approval-view.test.mjs` 265-332 (partner block; 323-331 "never says ... a real email was sent" stays for simulated), 833-838 (`APPROVAL_TEXTS` snapshot); `web/scripts/incident-view.test.mjs` 702-716 (compact band); `web/scripts/catalog.test.mjs` 80-101 (`RESULT_KEYS`, length 19 at 141), 134-135 (page key set, 75), 142ff (`PAGE_SLOTS` order), 268 (`SENTENCE_SLOT_KEYS`), 539-669 (`GOOD`/`WATCH` fixtures), 828-852 (`TEXT_SLOT_KEYS`).
- `web/e2e/settings/partner-contacts.spec.ts` 10-13, 58-75 (the GET simulation route); `web/e2e/support/partner-contacts.ts` 45-60. `web/e2e/cards/approval-card.spec.ts` A13 513-593 (fixture path, unchanged).

## Tasks & Acceptance

**Execution (in dependency order):**
- [ ] `Fix/PartnerContacts.cls` (DW-1393): `Parameter TABLE = 1;`; `Simulated(production)` (1 when the fixture names it); `For(production, namespace = "")`: a fixture production gives the fixture while `DemoOn()`, else []; the online demo gives [] without reading the table; otherwise `Data.PartnerContact.ForProduction(namespace, production)` de-duplicated by lower-cased trimmed address, first in ID order. `Named(production, id, namespace = "")` resolves through `For`. `Ids(contacts)` reuses `Joined`. Rewrite the class doc; keep it abstract with no write method.
- [ ] `Fix/Kind.cls`: add `ForApprover(incident, dryRun)` (default: unchanged) and `Shown(kind, incident, dryRun)` (dispatch like `ForName`; doc: runs in the production job, its result is stored, never traced). Add `Parameter MAILS = 0;`, base `Mail(row, Output recipients As %DynamicArray, Output subject, Output text, Output skipped As %DynamicArray) As %Boolean` (0, empty outputs) and `Mailed(row, ...)` (0 unless row is Kind `fix`, State `executing`, `ForName(row.FixKind)` registered with `MAILS` 1; then the kind's `Mail`; anything unreadable gives 0). Document the contract in the class doc (AD-14 amended).
- [ ] `Fix/Kind/Email.cls`: `MAILS = 1`; `Mail` returns `FixParameters.recipients` (only when an array of strings, else []), `subject`/`text` (the string member, else ""), `skipped` []. Move `Execute`'s Submit into public `SubmitApproved(row) As %DynamicObject` ({sent, outcome, message}); `Execute` calls it. No behaviour change.
- [ ] `Fix/Kind/PartnerWarning.cls`: `Facts` drops the Partner line; `SYSTEMNOTE`'s first sentence as in Always; `CheckParameters`: `to` is ids; `DryRun` reads `For(incident.Production, incident.Namespace)`, requires `to` = `Ids`, targets = ids, result `{"notice", "recipients": [ids], "simulated": Simulated(production)}`; `ForApprover` swaps the ids for `{id, name, address}` and drops an id that no longer resolves; `Ready`: fixture production -> today's rule (demo mode); table production -> 1 when `SettingsOps.IsAddress(Data.Setting.Fresh("email.address"))` and not `OnlineDemo()`, else `NOTSETUP`; add `MailboxConnected()` (the same predicate, for `Notice` and `In`); `MAILS = 1` and `Mail` per Always (codes `removed`/`changed`, reason `NOSTART`, no name); add `OutReason(reason)` (1 when the reason is one of `Channel.Email.Out`'s `MESSAGE*` sentences, read with `$Parameter`, never copied); `Plan`: Settings-contact targets are always skipped with `NOSTART` (EXECUTE_GUARD), fixture targets keep today's rule matched by id at its position in `to`. Update the class doc.
- [ ] `Channel/Email/Out.cls` (ruled Lane B edit): `Approved`, `ApprovedRecipients` and `Authorised` take the row's recipients, subject and text from `##class(OcuTalon.Fix.Kind).Mailed(row, ...)` (recipients joined by commas for `Listed`; a "" subject or text means the row does not hold it, as today). Update the doc paragraphs at 11-24 to name the mail method instead of `FixKind` `email`. Nothing else in the file changes.
- [ ] `Fix/Executor.cls` (minimal, plain union with 24.4a): in `Run`'s contact branch, after `Ready` and `AsApproved` pass and the production is not `Simulated`, call a new private method `SendPartner(row, class, incident, run, total)` instead of `Check`/`Carry`/`Deliver`: `Fix.Kind.Mailed(row, ...)` 0 -> could not start `NOSTART`; no recipient -> `Finish` done {total, completed 0, skipped total, reason `FirstReason(skipped)`}; else the new seam `Method MailApproved(row) As %DynamicObject [ Private ]` (calls `Fix.Kind.Email.SubmitApproved(row)`): sent (Ok 1) -> `Finish` done {total, resent 0, completed recipients, failedAgain 0, skipped skipped count, reason `FirstReason(skipped)`, outcome}; not sent -> `Finish` failed {total, completed 0, reason the CommandResult's message, outcome}; an exception -> failed with Out's `MESSAGEFAILED`. `ActionTarget` 824: " (simulated)" only when `Simulated(incident.Production)`. Update doc 62-68.
- [ ] `Watch/Notice.cls`: `KEYPARTNERKEPTREQUEST` (`incident.partnerRequestKept`), `KEYPARTNERMAILREQUEST` (`incident.partnerRequestMailbox`), `KEYPARTNERSKIPPED` (`result.partnerSkipped`), and the two `fix.email*` keys by reference to their catalog names; `AskedKey(kind, dryRun = "")`: `partner_warning` with `simulated` not 1 gives the mail key when `PartnerWarning.MailboxConnected()`, else the kept key; `AskedSlots` resolves its key with `AskedKey(kind, dryRun)` and gives `{production, notice}` for both; `ResultKey(state, result, kind, simulated = 1)`: contact kind with `simulated` 0 -> kept (failed with `NOTSETUP`) / `fix.emailSent` (Completed = Total > 0) / `result.partnerSkipped` (state done, Skipped > 0) / `fix.emailNotSent` (`OutReason`) / `result.partnerNotSent`; `ResultSlots`: `fix.emailSent` {}, `fix.emailNotSent` {reason}, `result.partnerSkipped` {sent: Completed, skipped: Skipped, total: Total}. Doc 49-52. Then search `src/` for every list of the request-key family that holds `incident.partnerRequest` (Telegram Out's request-key handling, `Test.Msg.Catalog` 523) and add both new request keys beside it.
- [ ] `Watch/IncidentManager.cls`: the five hooks of the Code Map, and nothing else.
- [ ] `Watch/Summary.cls` 190: a contact run whose request row's production is not `Simulated` and that has Completed > 0 uses the approved `summary.fixEnded` (its counts) instead of `summary.partnerSent`; kept and not-sent are unchanged. Doc line 13.
- [ ] `Msg/Catalog/Watch.cls`: append `incident.partnerRequestKept` (ruled texts, `### For the Planner's gate` (b)). Append `incident.partnerRequestMailbox` and `result.partnerSkipped` ONLY after the Planner approves them (gate (b)), verbatim. `Msg/Catalog/Core.cls`: append `press.approvedPartnerKept` (ruled).
- [ ] `Channel/Telegram/In.cls`: `FixSlots` carries `simulated` (from `FromRow(row).DryRun.Simulated`) for `partner_warning`; `PressText`: simulated -> `press.approvedPartner`; not simulated and `MailboxConnected()` -> "" (no text); else `press.approvedPartnerKept`.
- [ ] `web/src/app/approvals/approval-view.ts`: `partnerView` gives no pending note when `simulated` is false; `resultView`/`partnerResultView` take an optional `simulated` (true when absent keeps today's bands): with `simulated` false the bands are `bandOf('fix.emailSent')` (all sent, success), `bandOf('result.partnerSkipped', {sent, skipped, total})`, today's `result.partnerKept` band, `bandOf('fix.emailNotSent', {reason})` for a reason that ends with "." (Out's sentences) and today's `result.partnerNotSent` otherwise. With `simulated` unknown (undefined from a caller that can't tell) a band with Completed > 0 is not shown. Update docs 30-33 and 563-566.
- [ ] `web/src/app/approvals/approval-request-card.ts` 534: pass `this.shown().dryRun?.simulated`. `web/src/app/incidents/incident-card.ts` 34 / `incident-view.ts` 100, 454: pass `approvals()?.[request.ref]?.dryRun?.simulated` (undefined when the store lacks it).
- [ ] `web/scripts/catalog.mjs`: add `fix.emailSent`, `fix.emailNotSent` (also `TEXT_SLOT_KEYS`) and, once approved, `result.partnerSkipped` to `LISTED_KEYS`; run `npm --prefix web run catalog`; update `web/scripts/catalog.test.mjs` (`RESULT_KEYS`, counts, `PAGE_SLOTS`, `TEXT_SLOT_KEYS`, the `GOOD`/`WATCH` fixtures).
- [ ] `ci/mock/scenarios/B/partner-notice-draft.json`: the new first sentence as `match.prompt`.
- [ ] `Test/Fix/ExecutorProbe.cls`: override `MailApproved` (records the call count and the row Ref; answers `^||` canned `{sent, outcome, message}`, default sent).
- [ ] NEW `Test/Fix/PartnerMail.cls` (warm, no production; saves and restores `email.address`, `email.owner` and `onlineDemo` as `Test.Channel.EmailOut` 82-99 does; uses `Test.Channel.EmailOutProbe` through a shadow `OnSendEmail` as `Test.Channel.EmailOut.Send` 1372 does; copy its private instance helpers `Send` 1372 and `Approval` 1406 (and the `Mailbox`/`Delivered`/`Claims`/`Reset` pattern) with the reason "private helpers of a Lane B test class"; `zzpc` contacts on a `ZZNS`/`ZZPROD` incident and an executing `partner_warning` row whose `DryRun` holds the stored addresses). Methods, one per pin: `TestSameAddressIsSent` (SENT at Out: Delivered 1, to exactly the two stored addresses, text = notice, subject = the approved subject), `TestRemovedContactIsSkipped`, `TestChangedAddressIsSkipped` (the new address never appears in any recorded send), `TestAllSkippedSendsNothing` (refused recipients, Delivered 0), `TestOnlineDemoRefusesPartnerWarning` (DEMO_REFUSED), `TestFixtureIsNeverMailed`, `TestOneSendPerApproval` (second `OnSendEmail` already_sent, one Delivery row), `TestLogHoldsNoContact` (the `TestNoPersonalDataInTheLog` pattern for the names and addresses).
- [ ] `Test/Fix/PartnerWarning.cls`: update the moved pins (method list, `SYSTEMNOTE`, Facts without "Partner:", `to` as ids, recipients as ids, the tampered case); add kind-level tests with `zzpc` rows for SETTINGS_HAPPY, DEDUPE (DW-1393), OTHER_SCOPE, NO_CONTACTS, EXECUTE_GUARD, DEMO_FIXTURE with a table row for Orders, ONLINE_DEMO_TABLE; executor-level tests through `ExecutorProbe` for SENT (done, Completed 2, one `MailApproved`), KEPT (no mailbox: `NOTSETUP`, no `MailApproved`), SKIPPED_REMOVED, ALL_SKIPPED (no `MailApproved`), SEND_FAILED (canned not sent -> failed with that message), and the `ResultKey`/`ResultSlots` choice for each; the literal pin (DW-1394): `$Parameter("OcuTalon.Fix.PartnerContacts","TABLE")` = "1" and `SettingsOps.PartnersShown()` = 1.
- [ ] `Test/Fix/PartnerDraft.cls`: update 143 and 175-191 (`to` = "1", recipients [1], slots from the resolved row); add a Settings-contact draft whose Decide input and `DryRun`/`Notification` messages hold neither name nor address, key `incident.partnerRequestKept` with no mailbox and `incident.partnerRequestMailbox` with one, the row's `DryRun` holding both.
- [ ] `Test/Fix/PartnerTurns.cls`: update 74-76 (ids). Add `TestSettingsContactsLeakNothing` (kept: no mailbox; a resolved incident on `ZZPROD` in `OCUORDERS`, two `zzpc` contacts with unique names and addresses plus one duplicate address; the asked turn raises one request with one id per address; approve -> `result.partnerKept`, no mail; scan each name and address: `TraceLeaks` "", no audit entry, no `Ens_Util.Log` text, `Leaks` exactly the contact row's, the approval row's and the live-event globals) and `TestSettingsContactsSentOnce` (mailbox connected with `Test.Fix.Email`'s `Connect`/`Disconnect` and the CI mock SMTP: approve -> the mock holds exactly one email, From the mailbox, To the two de-duplicated addresses, the text byte for byte; `fix.emailSent`; one Delivery row; the same leak scan, which must still find only those three globals).
- [ ] `Test/Msg/Catalog.cls`: counts (+1 Core for `press.approvedPartnerKept`; +1 Watch for `incident.partnerRequestKept`, +2 more once the two NEW keys are approved); request-key lists and the " Approve?" form.
- [ ] `Test/Channel/TelegramApproval.cls`: the press for a simulated-0 row with and without a mailbox.
- [ ] `web/scripts/approval-view.test.mjs`: no note for `simulated` false; the four simulated-false bands; today's bands for `simulated` true or absent; unknown `simulated` shows no sent band. `web/scripts/incident-view.test.mjs` 702-716: the compact band with the store's `simulated`.
- [ ] `web/e2e/settings/partner-contacts.spec.ts` (DW-1394): drop the `beforeEach` GET route 58-75 and rewrite the header 10-13; P1 asserts `realTable()` is "1", `partnerShown` is true, and both halves of `settings.partnersHelp` are visible on the real page; keep the per-test POST stubs.
- [ ] Search the test trees for the old shapes (`it@orders-partner.example` in `to`, `"to": "<address>"` partner rows, "Partner: Orders Partner IT", "named below", `FixKind` `email` assumptions in Out's tests) and update each one that the kind or Out re-validates.

**Acceptance Criteria:**
- **AC1 (TABLE, DW-1394).** Given the compiled class, when an admin of a non-online-demo install loads Settings, then `TABLE` is 1, `GET /api/v1/settings` carries `partner-contacts`, and Settings › Partner contacts shows after On call with both halves of `settings.partnersHelp`. On the online demo the member is still absent and the route still answers 409.
- **AC2 (only the listed contacts).** Given a warning for an incident of a watched production that is not the demo's, when it is raised, then its recipients are exactly that production's Settings contacts (namespace and production, de-duplicated by address), and nothing else is ever a recipient.
- **AC3 (ids, DW-1254).** Given a Settings-contact warning's whole lifecycle (ask, draft, raise, approve, then kept or sent), when the trace bodies, the event log, the audit log and the `^OcuTalon*` globals are scanned, then no trace, log or audit entry holds a contact's name or address. Only the contact row, the approval row and the approval live event hold them.
- **AC4 (the approver sees exact recipients).** Given a raised Settings-contact request, when the approver opens the card, then it shows every recipient as "Name <address>" and the exact notice. The chat or Telegram request text names none of them.
- **AC5 (sent once, only after approval).** Given a mailbox connected in Settings > Channels > Email, when the request is approved, then exactly one email goes from that mailbox to the approved addresses with the approved text byte for byte, one Delivery row records it, and the user reads `fix.emailSent`; a second send for the same approval sends nothing. Before approval nothing is sent, and `Execute` with no approved row does nothing.
- **AC6 (kept when no mailbox).** Given no mailbox is connected, when the request is raised and approved, then the request text is `incident.partnerRequestKept`, nothing is submitted or delivered anywhere (the Simulated mailbox included), the row keeps the text, the user reads `result.partnerKept`, and the Telegram press reads `press.approvedPartnerKept`.
- **AC7 (approved-address rule).** Given an approved request, when a recipient was removed or its address changed after the request was raised, then that recipient is skipped and reported (`result.partnerSkipped`, counts only), nothing goes to the new address, and when every recipient is skipped nothing is sent and the result says so.
- **AC8 (the online demo and the demo).** Given the online demo, when a `partner_warning` system send reaches EmailOut, then it answers `not_available` and sends nothing. Given the Orders production with demo mode on, when "Warn the partner" runs, then 23.5's flow, its texts and its Simulated-mailbox send are unchanged, and no fixture contact is ever mailed for real. The draft's facts no longer name the partner.
- **AC9 (the email kind unchanged).** Given Story 22.7's `email` requests, when they are sent through the widened EmailOut, then every existing outcome of `Test.Channel.EmailOut` and `Test.Fix.Email` holds.
- **AC10 (integration: consumers).** Given `TABLE = 1`, then `SettingsOps.PartnersShown()` (consumer: the Settings page) shows the section; `IncidentManager` (consumer: the reader) raises a request whose targets are the listed contacts' ids; and `Channel.Email.Out` (consumer of `Fix.Kind.Mailed`) sends a `partner_warning` row's approved addresses.

### Review Findings

Code review (epic-cycle stage, 2026-11-15): four layers on the full-opus tier (blind-hunter, edge-case-hunter, verification-gap, acceptance-auditor), diff `3d5b7145d..13da5d2cd` plus QA's Verification lines. 26 layer rows plus one Rule 2 check of the reviewer's own; 14 entries after grouping (high 0, med 6, low 8), 10 rows rejected. The approved-address rule held under every adversarial case (case and spaces, a contact moved to another production or namespace, an id reused after delete, a tampered row, approval before send, the online demo, the fixture). Decision-needed items were resolved by Rule 15 (decision-pending in the ledger, not blocking); every patch was applied (checkpoint option 1).

- [x] [Review][Patch] (med, AC8) The chat panel's announcements lost the demo's sent band: `announce` built `incidentContext` with no approvals, so `simulated` was null and `partnerResultView` hid "Sent to the Simulated mailbox." (and a real send's band) [web/src/app/chat/chat-panel.ts:449] — fixed: passes `this.live.store()?.approvals`; source pin added to `web/scripts/approval-sources.test.mjs`.
- [x] [Review][Patch] (med, Rule 19) The Settings-contact tests assert exact contact sets on shared ZZNS/ZZPROD and ORDERS/ZZPROD keys and never cleaned first, so a stopped run's `zzpc` rows turn later runs red [src/ocutalon/cls/OcuTalon/Test/Fix/PartnerSupport.cls:44] — fixed: `SaveMailbox` calls the new `Sweep` (removes every `zzpc` contact).
- [x] [Review][Patch] (med, Rule 19) `TelegramApproval:TestApproveKinds`, `PartnerDraft:TestSettingsContactsDraft` and `PartnerTurns:TestSettingsContactsLeakNothing` relied on the online-demo flag being off without setting it [src/ocutalon/cls/OcuTalon/Test/Fix/PartnerSupport.cls:44] — fixed: `SaveMailbox` sets `onlineDemo` 0 (`RestoreMailbox` puts it back).
- [x] [Review][Patch] (low) A failed send dropped the recipients that `Mailed` had skipped (`"skipped": 0`), so the run's counts did not add up [src/ocutalon/cls/OcuTalon/Fix/Executor.cls:555] — fixed: the failed branch carries `skipped.%Size()`.
- [x] [Review][Patch] (low) `Fix.PartnerContacts.Addresses` and `Names` had no product caller left (a name-and-address joiner is what DW-1254 forbids in traced text) [src/ocutalon/cls/OcuTalon/Fix/PartnerContacts.cls:82] — removed; the class doc and the `PartnerWarning` method-list pin follow.
- [x] [Review][Patch] (low) EmailOut's `FIXKIND`/`FIXRECIPIENTS` doc said "other code reads both"; EmailOut reads neither now and no product code reads `FIXRECIPIENTS` [src/ocutalon/cls/OcuTalon/Channel/Email/Out.cls:75] — doc corrected (the ruled doc line; no code change).
- [x] [Review][Patch] (low, Rule 19) `Test.Fix.PartnerMail` never added its incidents to `Refs`, so each run left ZZNS incident rows behind [src/ocutalon/cls/OcuTalon/Test/Fix/PartnerMail.cls:156,246] — fixed.
- [x] [Review][Patch] (low, Rule 19) `PartnerTurns.OnAfterOneTest` ran the mailer's `OnAfterAllTests`, which restores the runner keys, while the class's own `Pointed` stayed 1, so a later turn test would not re-point the runners [src/ocutalon/cls/OcuTalon/Test/Fix/PartnerTurns.cls:85] — fixed: `Pointed` is reset.
- [x] [Review][Patch] (low, AC6) A `partner_warning` press whose `simulated` slot is missing (dry run unreadable) read the Simulated-mailbox sentence, false for a Settings contact [src/ocutalon/cls/OcuTalon/Channel/Telegram/In.cls:516] — fixed: no text without the slot.
- [x] [Review][Defer] (med) DW-1415: a Settings-contact `partner_warning` mails outside addresses, but `Fix.Kind.Email.MayApprove` (DW-1262's admin-only rule) passes every kind but `email`, so any asker can approve it [src/ocutalon/cls/OcuTalon/Fix/Kind/Email.cls:328] — deferred: decision-pending owner=burndown, a Planner call on privileges (the recipients are admin-curated; no ruling covers the approver).
- [x] [Review][Defer] (med) DW-1416: the timeline reads `summary.partnerNotSent` ("the delay notice was not sent.") after EmailOut's `MESSAGEMAYHAVESENT`/`MESSAGEFAILED` [src/ocutalon/cls/OcuTalon/Watch/Summary.cls:195] — deferred: decision-pending owner=burndown, needs a Planner text ruling; the session and the card show Out's own sentence.
- [x] [Review][Defer] (med, Rule 2) DW-1417: `Test.Fix.PartnerMail` copies Lane B's private `Test.Channel.EmailOut` helpers (`Delivered`, `Claims` verbatim; `Send`, `Mailbox`, `Reset` adapted), a copy the spec forces [src/ocutalon/cls/OcuTalon/Test/Fix/PartnerMail.cls:257] — deferred: routed owner=burndown (unify, as DW-603).
- [x] [Review][Defer] (low) DW-1418: `Core/CommandsIn.cls`'s class doc still calls a system `SendEmail` the approved email fix's only [src/ocutalon/cls/OcuTalon/Core/CommandsIn.cls:1] — deferred: wontfix-accepted, out of footprint (reopen_if in the ledger).
- [x] [Review][Defer] (low, Rule 19) DW-1419: the web glue that passes `simulated` to the bands (`incidentContext`, the request card) has source pins only; no executed test drives store, card and band [web/src/app/incidents/incident-card.ts:41] — deferred: wontfix-accepted (reopen_if: the smoke or a live run shows a partner band missing or wrong).

Rejected:
- (low) Out.`Approved` treats an empty row subject or text as not held (acceptance 2): unreachable, since `Email.CheckParameters` requires 1 to 200 characters, and a failed `partner.emailSubject` render leaves the command with no subject, which `Check` refuses; spec-bound ("as today", review blind 1).
- (low) Hunks beyond the hook lists (acceptance 3): doc paragraphs, `Summary.EndedSlots` and the `mailing` flag behave as specified; a merge-tree against `OCT-epic24` conflicts only on the ruled `Shown` hook line, so no named harm.
- (false) `MailboxConnected` trims but Out does not (acceptance 5, edge 4): `SettingsOps` trims and validates `email.address` before it stores it (SettingsOps.cls:1864-1869), so a stored address never has outer spaces.
- (low) A contact removed between Out's `Authorised` and the SMTP hand-off still gets its approved address (acceptance 6, first gap): a millisecond window, never a new address; theoretical.
- (low) A lower-id contact changed to an approved contact's address makes that contact read `removed` at send time (acceptance 6, second gap; edge 2): needs an admin to duplicate an address after approval, errs on the safe side (under-send), and the fix adds a second, un-de-duplicated reader.
- (by-design) More than 20 contacts are refused by Out at send time (edge 1, edge 8): Design Notes "Decided in-stage" ("no dry-run guard is added").
- (by-design) Fixture traces still name the fictional contact (edge 7): AC8 keeps 23.5's flow and `incident.partnerRequest` naming it; DW-1254 concerns real contacts.
- (low) `ForApprover` re-reads the contacts once per id (blind 7): a handful of contacts at raise time; the fix restructures the loop.
- (low) The earlier triage line "intent 1" cites an `id` member that `Test.Live.Payloads` does not have (verification-gap, other 2): `Live.Payload.Approval` reads only `name` and `address`; the fix would edit this spec's log.
- (dup) The chat-announcement finding of verification-gap ("Other findings" 1) is the first patch above.


**Rework iteration 1 (Contest Planner ruling ~05:15Z 2026-11-16, prompts/dw-1415-1416-rulings-20261116.md; 1.0.12 CUT items; BINDING). Three items, kept in SEPARATE FILES where possible so the lead can commit them separately; list under `## Auto Run Result` which files belong to which item:**
- [x] [Review] DW-1415 (CUT BLOCKER) -- REQUIRE OcuTalonAdmin to approve a partner warning, with the same rule and check as kind email: reuse or generalise `Fix.Kind.Email.MayApprove` (NO second copy; the self-approval rule stays exactly as it is for email). Enforce it server-side on every approval path (web, phone, Telegram). A non-admin's approve is refused with email's EXISTING refusal text (no new string), sends nothing, keeps no approved draft, and is audited with ids only. Deny is unchanged (open to whoever may deny today). Pins, each with a demonstrated mutation: a non-admin requester cannot approve their own warning, on each path (web, phone, Telegram); an admin can; a role revoked between the request and the approval is refused at approval time.
- [x] [Review] DW-1416 -- the incident timeline follows EmailOut's answer for a partner warning: Sent → the existing line; Failed → "not sent" ONLY if EmailOut's "failed" means the message was definitely not handed to the mail server (read `Channel/Email/Out.cls` MESSAGEFAILED / MESSAGEMAYHAVESENT semantics and say which); May-have-sent → a NEW line saying so and telling the user to check the connected mailbox's Sent folder before asking again (Planner's example: "The delay notice may have been sent. Check the mailbox's Sent folder before sending it again."). If kind email ALREADY has a may-have-sent line, reuse its wording EXACTLY instead. The line holds no recipient, subject or text (ids only); may-have-sent never re-sends automatically. Pins and mutations for all three answers. Record the FINAL may-have-sent line verbatim (key and file) in Design Notes for the PART READY report.
- [x] [CI] shards-11 rebalance (tests only; do NOT raise any limit) -- shards-11 took 31m18s against its 32-minute limit on run 43794653657 (shard:lane-a@Fix + live:cards). Move `Test.Fix.PartnerMail` (or another Lane A class) out of shards-11 to a lighter shard (measured in that run: shards-3 21.4 min, shards-7 23.5 min; others 26.8-31.9 min) through `ci/units.sh`'s Lane A entries only, following its own area/shard rules and comments (update the planned-seconds comment if the file keeps one); `bash docker/tests/test-ci-config.sh` (or the file's own checks) must pass and `ci/iris.sh classes <shard>` must show the class in its new shard and not in shards-11.


**Code review, rework iteration 1 (epic-cycle stage, 2026-11-16; re-review 1 of 3).** Four layers on the full-opus tier (blind-hunter, edge-case-hunter, verification-gap, acceptance-auditor), diff `dbc68f1d4..HEAD` (b39c8121 shards-11, 5b40e533 DW-1415, 7d7df952 DW-1416), checked against the Planner ruling `prompts/dw-1415-1416-rulings-20261116.md`. 27 layer rows; 10 entries after grouping (high 1, med 3, low 6), 15 rows rejected. No HIGH remains after the patches. The DW-1415 and DW-1416 Defer lines above are resolved by this rework.

- [x] [Review][Patch] (high, Rule 3, DW-1415) The web and phone refusal of a non-admin's approve was pinned only in-process (`PartnerApprove.Post`, the test process's own user); no real-HTTP test [web/e2e/api/approver.spec.ts] — fixed: AP6, over real HTTP on a fresh stack: the LIVE user (OcuTalonUser only) approving its own partner warning to Settings contacts gets 403 `not_allowed` with "Only an OcuTalon admin can approve this email.", the request stays pending and unanswered, one Action entry records the refusal with ids only (no name, address or notice); the README admin's approve of its own warning is 200 `done` and approved by the admin. Mutation recorded under Verification.
- [x] [Review][Patch] (med, Rule 19) A run of the demo's simulated contact that a restart cut short was not pinned to "not sent": moving the `Interrupted` clause outside the `Simulated` guard stayed green [src/ocutalon/cls/OcuTalon/Test/Watch/Summary.cls:861] — fixed: the demo half of `TestSettingsContactMayHaveSent` gains an interrupted run and expects `0|2`; mutation recorded.
- [x] [Review][Patch] (low, Rule 19) The "no Delivery and no FixRun row" count after a refused approve cannot fail: a fixture row has no hold, so even an approved one never runs [src/ocutalon/cls/OcuTalon/Test/Partner/PartnerApprove.cls:246] — fixed: removed from `AssertUntouched` (and kept out of AP6); "nothing sent or kept" rests on the request staying pending and unanswered, which the mutations above already turn red.
- [x] [Review][Patch] (low) The `ci/units.sh` header said `shard:lane-a@rest` takes any area added to lane-a later; Partner is named in shards-7's piece [ci/units.sh:32] — comment corrected.
- [x] [Review][Patch] (low) `MayApprove` was restructured and `AnswerOps.Carry` changed, but the Raise caller's class and the AnswerOps probe class were not re-run — run on warm `e23b13cr2w`: `Test.Fix.Email` passed (34 s), `Test.Core.AnswerPrecedentsProduction` passed (27 s).
- [x] [Review][Patch] (low) DW-1417 still named `Test.Fix.PartnerMail` — a ledger note records the move to `Test.Partner.PartnerMail`.
- [x] [Review][Defer] (med) `shard:lane-a@Docs,Partner` is a two-area unit of about 1,246 s, above Story 0.20's 900 s for a unit of two or more areas; a Partner piece of its own would take shards-7 to about 33.7 min or shards-3 to about 31.6 min (inference) [ci/units.sh:138] — deferred: the exception is now written in `ci/units.sh`'s rebalance comment; DW-1032 occurrence (routed owner=burndown, below its 1,400 s trigger).
- [x] [Review][Defer] (med) DW-1422: `Sender.Classify` maps a QUIT-stage `SMTPResponse` (the server already took the message with 250) to REJECTED, so EmailOut answers `MESSAGEREJECTED` and the timeline reads "the delay notice was not sent." for a delivered notice [src/ocutalon/cls/OcuTalon/Channel/Email/Sender.cls:151] — deferred: routed owner=burndown; the fix is in EmailOut's classifier (Story 21.11's file, out of this epic's footprint) and corrects email's own sentence too; rare (a server that does not answer QUIT).
- [x] [Review][Defer] (low) DW-1423: `docs/security-overview.md` does not name the admin rule for a partner warning or the refused-approve Action entry [docs/security-overview.md:151] — deferred: wontfix-accepted, ruled public text (reopen_if in the ledger, with a draft line).
- [x] [Review][Defer] (low, Rule 2) DW-1424: `PartnerApprove` repeats the user and role helpers that about nine test classes already copy [src/ocutalon/cls/OcuTalon/Test/Partner/PartnerApprove.cls:290] — deferred: wontfix-accepted (an existing project pattern; reopen_if DW-1417's unification is scheduled).

Rejected (rework re-review):
- (false) A demo row raised before 1.0.12 has no `simulated` member, so a non-admin would be refused on the demo (edge 1): 23.5's dry run always wrote `simulated` 1, and `DRYRUNKEYS` has kept it since.
- (low) A non-admin's approve of a partner warning that is no longer pending reads the admin refusal and writes a refused entry (edge 2): the same as email today; gating on pending would change email's path, which the ruling keeps as it is.
- (low) A `not_allowed` from Answer's own RequiredRole check after rule 6 passed reads the admin sentence (edge 3): needs the role taken away within the milliseconds between two checks; email behaves the same; theoretical.
- (by-design) The may-have-sent line does not reuse `MESSAGEMAYHAVESENT` (edge 5): kind email has no timeline line; the new line is the Planner's example, as ruled.
- (low) `AdminRuled` names the gated kinds and reads the partner dry run's shape (blind 4); `RunEvents` calls `MayHaveSent` on any contact kind, which only `PartnerWarning` defines (blind 5): one contact kind and two mailing kinds today; theoretical until a new kind with MAILS 1 or TARGETTYPE contact is added.
- (low) The rework's Auto Run Result paragraph sits above the earlier pass's Summary (blind 6); the Never line does not name the `Core/AnswersIn.cls` and `Core/AnswerOps.cls` edits (acceptance 5); stale spec frontmatter and Review Triage lines (acceptance 6): each fix edits the spec under review.
- (low) GUIDE.md's partner bullet still says no notice is drafted without demo mode (blind 2): outside this rework's diff and not HIGH; noted for the Planner in the stage's closing summary.
- (dup) The shards change has no mutation line (verification-gap Rule 19); the route legs use the test process's user (verification-gap 3a, now also covered by AP6); the namespace-wide task-warning clean-up (3b); `MayHaveSent` lists may-have-sent reasons instead of not-sent ones (acceptance 3); "simulated" read from the dry run, not the production (acceptance 4): adjudicated in the rework's own review pass (verification-gap 1, 3a, 3b; edge 2; blind 5). Re-checked for the "simulated warning is not asked" call: a partner row's `DryRun` has one writer, `IncidentManager.RaiseFix` (`StoredDryRun`), from the kind's own `DryRun`, whose `simulated` is `PartnerContacts.Simulated(incident.Production)`, the same predicate the executor and `Mail` use to decide never to mail; an unreadable or missing flag counts as not simulated, so a row of a real production cannot read as simulated.


**Rework iteration 2 (CI red on 0c743465, ci run 43816599381, story class):**
- [ ] [CI] iris(production) job 133129955974, `shard:lane-a@Channel`: `OcuTalon.Test.Channel.TelegramApproval` `TestApproveKinds` fails for `partner_warning` ("the text of the answer"; "the request is approved on the channel telegram" x2) since DW-1415 made a non-simulated partner warning admin-only. Update the test on this shared surface so it stays true to the ruling: the Telegram approve of a non-simulated partner warning by a non-admin is refused with email's refusal text and stays pending, and an admin's (or a simulated demo-contact warning's) Telegram approve still approves — whichever the test's fixture is meant to cover; never weaken the DW-1415 rule. Grep the other test classes on shared surfaces (approve paths: `Test.Channel.*`, `Test.Core.Answer*`, `Test.Web.*Approval*`, web e2e approval specs) for the same assumption that a non-admin can approve a partner warning, and fix any found. Run each touched class on a lane-B warm stack.

## Spec Change Log

- 2026-11-16 ~07:00Z (lead, rework iteration 2 of 3, trigger: CI story red on 0c743465): TelegramApproval TestApproveKinds partner_warning after DW-1415.

- 2026-11-16 ~05:20Z (lead, rework iteration 1 of 3, trigger: Planner ruling DW-1415/DW-1416/shards-11, 1.0.12 cut items): re-opened.

- 2026-11-16 ~00:35Z (lead): Planner approved the re-plan: lines 1 and 2 verbatim; D9 partner.emailSubject "Delay notice" with a pin that a real send never uses the Simulated subject; D6-D8, D10 accepted.

- 2026-11-15 (plan stage, re-plan of the send path under the 23.13 GATE and "23.13 EmailOut" rulings): the dependent Boundaries lines (Settings-contact requests, Other text, the first and third Never lines) and the matrix rows SETTINGS_HAPPY, KEPT, TAMPERED were re-planned to agree with the two binding amendments, each marked [RE-PLANNED]; rows SENT, SKIPPED_REMOVED, SKIPPED_CHANGED, ALL_SKIPPED, SEND_FAILED, ONE_SEND_PER_APPROVAL, DEMO_REFUSED, FIXTURE_NOT_MAILED and EMAIL_UNCHANGED added. Code Map, Tasks, ACs (AC5-AC10), gate and Verification rewritten for the mail method, Out.cls, the executor branch and the texts. KEEP: the source rule, ids in traces, the approver hook, count-only logs, vetoes 1/3/4 and deviations 1-5 as approved.

- 2026-11-15 ~23:58Z (lead, Planner "23.13 EmailOut" ruling): option (i) approved; AD-14 amended in the spine; approved-address security condition; two new lines to draft; status reset to draft for the re-plan.

- 2026-11-15 ~23:35Z (lead, Planner 23.13 GATE): veto 2 changed (send through 21.11 EmailOut when a mailbox is connected; kept only when none); intent block amended; status reset to draft for a re-plan of the changed part.

## Review Triage Log

### 2026-11-15 — Review pass
- verdicts: 36 findings — high 0, medium 2, low 23, false 11, maybe-false 0
- findings:
  - `[low]` `[reject]` blind 1: Out.Approved treats a row's empty subject or text as not held — spec-bound (the ruled `Email.Mail` gives "" for a member that is not a string), unreachable through the executor (its command carries neither), and Check refuses an empty value anyway; the fix adds a held flag to the mail method.
  - `[low]` `[reject]` blind 2: the mailbox can be connected between the ask and the approval — the Planner's conditional wording of `incident.partnerRequestKept` is verbatim and says so; the other order is harmless.
  - `[low]` `[reject]` blind 3: result bands hide when the approval payload is not in the store — recorded in Design Notes as accepted (null hides a band that claims a send); the demo's own bands are unchanged where the payload is present.
  - `[low]` `[reject]` blind 4: the web decides "EmailOut sentence" by a trailing full stop, the server by exact sentence — the only other failed-run reasons (NOSTART, NOREAD, NOTSETUP) carry none; a mismatch needs a new reason with a stop.
  - `[false]` `[reject]` blind 5: a missing `simulated` reads as not simulated — `PartnerWarning.DryRun` always writes it, and the row's DryRun is written only there.
  - `[false]` `[reject]` blind 6: MailAllowed counts real recipients — the spec (Design Notes, De-duplication) rules that `MailAllowed` counts the de-duplicated list.
  - `[low]` `[reject]` blind 7: Completed comes from the executor's own Mailed read, Out reads again — a contact edited inside that window; Out refuses on a mismatch and sends nothing, so no wrong address is mailed; the fix needs a result channel from Out.
  - `[false]` `[reject]` blind 8: address comparison is case-sensitive — the spec rules "exactly that address (trimmed, case-sensitive)".
  - `[low]` `[reject]` blind 9: no test sends a command carrying its own subject, text or recipients for a Settings row — the refusal is Out's generic Approved/Authorised path, pinned by `Test.Channel.EmailOut` for email rows; a Settings row goes through the same code.
  - `[false]` `[reject]` blind 10: rulings dated 2026-11-16 — the spec's own Planner rulings carry that date (Spec Change Log, Design Notes).
  - `[low]` `[reject]` edge 1: executor and Out read the row twice (same root as blind 7).
  - `[low]` `[reject]` edge 2: ForApprover with every id gone raises an empty card — needs a contact deleted between the dry run and the raise inside one job; the run then ends skipped and nothing is sent.
  - `[false]` `[reject]` edge 3: Telegram reads a missing `simulated` as 0 (same as blind 5).
  - `[low]` `[reject]` edge 4: bands hide with no approval payload (same as blind 3).
  - `[low]` `[reject]` edge 5: `endsWith('.')` (same as blind 4).
  - `[false]` `[reject]` edge 6: web `>=` against the server's `=` for completed and total — completed never exceeds total.
  - `[low]` `[reject]` edge 7: Summary.RunEvents with an unreadable incident reads the Simulated line — the incident just ran; needs its row deleted.
  - `[low]` `[reject]` edge 8: a contact with an empty address is the first of its dedupe key — the Settings save validates the address (Lane B); it would be skipped as removed at send time.
  - `[false]` `[reject]` edge 9: a case-only address change is skipped as changed (same as blind 8).
  - `[false]` `[reject]` edge 10: a mailing run with `failed` set — `failed` is only set by the Check/Carry branch, which a mailing run never enters.
  - `[false]` `[reject]` edge 11: TelegramApproval with the onlineDemo flag on — the class sets and restores its own keys and passes on a fresh stack.
  - `[low]` `[reject]` edge 12: Out.Approved empty member (same as blind 1).
  - `[low]` `[reject]` edge 13: Email.Mail "no behaviour change" claim (same as blind 1).
  - `[false]` `[reject]` edge 14: partner.emailSubject is a fourth key — the Planner's D9 ruling names it.
  - `[false]` `[reject]` edge 15: SendPartner takes no incident — the signature is internal and the spec text is not code; fix would edit this build's spec.
  - `[low]` `[reject]` edge 16: Plan's Settings-contact branch is a guard with no second test — `TestSettingsContactsExecuteGuard` pins it.
  - `[medium]` `[patch]` verification-gap 1: the executor's could-not-start branch for a Settings row was unpinned — added `PartnerWarning:TestSettingsContactsTamperedRowCouldNotStart`; mutation (branch removed) red, restored.
  - `[medium]` `[patch]` verification-gap 2: the web wiring of simulated into the compact card's band was unpinned — two source pins added to `web/scripts/approval-sources.test.mjs`; mutation (context without approvals) red, restored.
  - `[low]` `[patch]` verification-gap 3: AC3 leak, session result, Summary, Telegram press, AC9 reversal and AC10 hook named in no mutation line — each applied, observed red, reverted; lines written under Verification.
  - `[low]` `[reject]` verification-gap 4: the tests share ZZNS/ZZPROD — each creates and removes its own `zzpc` rows in OnAfterOneTest; only a run killed mid-test leaves rows, as for every fixture of this area.
  - `[low]` `[reject]` verification-gap 5: AssertNoLeaks scans without waiting for quiet — each test waits for the result notice first, and the scans are absence checks over rows that exist by then.
  - `[low]` `[reject]` verification-gap 6: SentOnce strips trailing whitespace before comparing the text — `PartnerMail:TestSameAddressIsSent` compares byte for byte.
  - `[low]` `[reject]` verification-gap 7: AssertNoLeaks has an unused `sent` parameter — cosmetic, no failing outcome.
  - `[low]` `[reject]` verification-gap 8: Out.Approved empty member (same as blind 1).
  - `[low]` `[reject]` verification-gap 9: chat announcements get no sent band — recorded in Design Notes as accepted.
  - `[low]` `[reject]` intent 1: the row-to-card join is not run end to end — `Test.Live.Payloads` pins the payload reading name and address (an extra `id` member is ignored) and the web tests pin the card from that shape; the card's own code is unchanged.

### 2026-11-16 — Review pass (rework iteration 1: DW-1415, DW-1416, shards-11)
- verdicts: 21 findings — high 0, medium 1, low 20, false 0, maybe-false 0
- findings:
  - `[low]` `[patch]` blind 1: Design Notes said the Partner area runs in shards-3 — it runs in shards-7 (`shard:lane-a@Docs,Partner`); the bullet is corrected.
  - `[low]` `[reject]` blind 2: `MESSAGEUNREACHABLE` and `MESSAGEFAILED` also cover sends that never left — by design: the ruling keeps "not sent" only when the message was definitely not handed over, and Design Notes record the mapping as conservative.
  - `[low]` `[reject]` blind 3: the card and chat still read `fix.emailNotSent`/`result.partnerNotSent` with Out's sentence for such a run — the ruling names the incident timeline only; reopen_if the Planner extends DW-1416 to the card and chat.
  - `[low]` `[reject]` blind 4: `MayHaveSent` fails open for a new EmailOut sentence — theoretical; it becomes real when `Out` gains an ambiguous failure sentence, which would show in `TestMayHaveSent`'s list.
  - `[low]` `[reject]` blind 5: "simulated" has two sources (the row's dry run, the production) — `PartnerWarning.DryRun` writes the row's flag from `Simulated(production)` and nothing else writes it; a mismatch needs a tampered row.
  - `[low]` `[reject]` blind 6: the audit call names one kind in `AnswerOps.Carry` — one call, as ruled (ids-only audit of a refused partner approve); email's refusal stays unaudited as before.
  - `[low]` `[reject]` blind 7: the card offers Approve to a non-admin who is then refused — spec-bound: the ruling enforces on the server and the card is unchanged; email behaves the same.
  - `[low]` `[reject]` blind 8a: `AuditRefused` counts an empty `FixTargets` as one — a partner warning always has targets; no reachable row.
  - `[low]` `[patch]` blind 8b: the `ci/units.sh` comment said `PartnerApprove` moved — it is new; the comment is corrected.
  - `[medium]` `[patch]` edge 1: a Settings-contact run cut short by a restart (request `interrupted`) read "was not sent" — `Watch/Summary.cls` now ends it with `summary.partnerMaySent` (Interrupted above 0, not simulated); `TestSettingsContactMayHaveSent` gains an interrupted run, mutation recorded.
  - `[low]` `[reject]` edge 2: an empty or unknown reason reads "not sent" — a failed non-simulated contact run always carries `NOSTART`, `NOREAD`, `NOTSETUP` or an Out sentence; no other reason is written.
  - `[low]` `[reject]` edge 3: same as blind 5.
  - `[low]` `[reject]` edge 4: Email's Raise refuses a non-admin requester, this kind's does not — a raise-time refusal needs a new text, which the ruling forbids; the approve is refused with email's existing text.
  - `[low]` `[reject]` edge 5: each refused press writes an audit entry — one entry per refused attempt, as ruled; email's behaviour is unchanged.
  - `[low]` `[reject]` edge 6: the claim "not sent only if definitely not handed over" for an interrupted or empty reason — the interrupted part is patched (edge 1), the rest is edge 2.
  - `[low]` `[reject]` verification-gap 1: the shard rebalance has no mutation line or executable pin — the ruling asks a manual check (`ci/iris.sh classes`, `test-ci-config.sh`); reopen_if the classes drift back into `lane-a@Fix` and shards-11 nears its limit.
  - `[low]` `[patch]` verification-gap 2: `TestSettingsContactMayHaveSent` pinned the mapping by counts only — it now asserts the line of each run in order; mutation recorded (the counts alone stayed green).
  - `[low]` `[reject]` verification-gap 3a: the web and phone legs use this process's own user — the fixture needs a user that is no admin; a runner with the role fails the test loudly, and an admin's approve is pinned on every path through `AnswerOps`.
  - `[low]` `[reject]` verification-gap 3b: the clean-up removes every matching task warning in the namespace — the class runs only in throwaway stacks.
  - `[low]` `[reject]` verification-gap 4: a refused Telegram press shows the user no text — the same as email today (`Telegram.In` `not_allowed`); the ruling reuses email's behaviour.
  - `[low]` `[reject]` verification-gap 5: same as blind 2.
- intent-alignment: descriptive report only, no findings; its divergences are the items above (the gate applies to the kept-draft approval too, as ruled).

## Design Notes

**Governing ADs (Rule 6):**
- AD-14 as amended 2026-11-15 ("EmailOut's system send for fix kinds": the mail method, the approved-address rule, one send per approval, the online-demo refusal, count-only logs) and EmailOut's existing Rule (TLS, `not_connected`, `Check`, the claim);
- AD-16 (fixed kinds; the dry run stored in the row; the executor trusts the row; `partner_warning` parameters `text` and `to`; the "Partner-warning recipients and delivery" bullet with the sent-or-kept rule);
- AD-15 (`IncidentManager` the only writer, drafting through Draft/Decide);
- AD-11 (the row is the truth);
- AD-12 (the approval payload's `Notice`/`Recipients`/`Simulated`, no new field);
- AD-17 (the audit holds ids, no identities);
- AD-19 (partner contacts' fixed homes, the `TABLE` switch, the partner audit exception);
- AD-13 (no product-storage reads from the web process: the card's `simulated` comes from the stored payload);
- AD-24 (personal data never in a traced message);
- AD-25 (the online demo);
- AD-29 (lanes; `ForProduction` the cross-lane reader);
- AD-32 (producers never render; new keys are catalog keys);
- AD-33 (one owner per table: `SettingsOps` writes, Lane A only reads).

**Decided in-stage:**
- **Source by production, not by demo mode.** An incident's production never changes, so a request's ids always resolve against the same source, even if demo mode is toggled between the raise and the approval. A fixture id can never be read as a table row ID. The same predicate (`Simulated(production)`) picks the result keys, the summary line and the audit target.
- **Sent or kept is decided at `Ready` (approval time); the request text at raise time.** If the mailbox is disconnected between the two, the request kept says so in its result (`result.partnerKept`); if Out then answers `not_connected`, `fix.emailNotSent` gives Out's own sentence. Both are truthful.
- **One email per approval, to all sendable recipients.** Out's claim is per `ApprovalRef`, and its limit of 20 recipients applies: a production with more than 20 Settings contacts is refused by Out at send time (`fix.emailNotSent` with `MESSAGEREFUSED`); no dry-run guard is added.
- **The approved address is compared exactly** (trimmed, case-sensitive) with the contact's current address; a case-only change is skipped. The address sent to is the stored one. Skip entries carry a code (`removed`/`changed`) and the approved `NOSTART` reason, so `FixRun.Reason` holds no new text and no identity.
- **The executor computes the counts with the same `Mailed` call that Out makes** (one method, two callers). A contact changed in the instant between the two calls is still never mailed (Out re-checks); only the reported counts could differ (inference, accepted).
- **Results for a Settings-contact request are chosen by `simulated`**, passed from `IncidentManager` (the incident's production), `Summary` (the request's production) and the web (the payload's `simulated`); `Notice.ResultKey` stays pure.
- **No card note for Settings-contact requests, and no press text when a mailbox is connected.** The card can't tell whether a mailbox is connected without a new stored dry-run key (a veto item); the chat request text says it. The approved `APPROVAL_TEXTS.partnerKeptNote` is therefore not used (deviation 6).
- **Facts drop the partner line for both sources.** One invariant: the model never sees a contact.
- **De-duplication.** Lower-cased, trimmed addresses; the lowest id is kept. `MailAllowed` counts the de-duplicated list.
- **Implement stage (23.13), small choices:**
  - `Notice.AskedKey(kind)` with no dry run keeps today's `incident.partnerRequest` (a dry run that says `simulated` other than 1 gets the kept or mailbox key), so every existing caller and the pin of `TestNoticeKeys` stay as they were.
  - `Notice`'s two email result keys are string literals, not a `{##class(Core.BridgeSink).#KEY...}` parameter default: that default failed the first fresh image build (the class does not exist yet when `Notice` compiles).
  - `PartnerWarning.Mail` reads a stored recipient's id as any whole number (a JSON number or its digits), so a stored row written by another hand still matches; the address is the stored one, trimmed.
  - `OutReason` reads the sentences named by the kind's `OUTSENTENCES` parameter from `Channel.Email.Out` with `$Parameter`.
  - The web takes `simulated` as `boolean | null` (`true` when the argument is left out, as today; `null` when a caller cannot tell). `IncidentContext` gains an optional `approvals`, which `incidentContext` fills from the card's `approvals` input; the chat announcements have none, so no sent band is announced there (`null`).
  - A done run that skipped everyone reads `result.partnerSkipped` (sent 0) in the session and on the card (`state` done, `skipped` above 0), as `Notice.ResultKey` does.
  - `Summary.RunEvents` opens the incident of the request (`IncidentRef`) to ask `Simulated(production)`.
  - Test helpers: `Test.Fix.PartnerSupport` (a Settings contact row, its removal and the mailbox keys) is used by `PartnerWarning`, `PartnerDraft`, `PartnerTurns`, `PartnerMail` and `TelegramApproval`; `Test.Fix.Email.Setup` is public so that `PartnerTurns.TestSettingsContactsSentOnce` connects the mailbox through an instance of `Test.Fix.Email` made with the running manager (`%New(..Manager)`) and puts it back with its `OnAfterOneTest`.

**Rework iteration 1 (DW-1415, DW-1416, shards-11; Contest Planner ruling 2026-11-16, BINDING):**
- DW-1415: `Fix.Kind.Email.AdminRuled(row)` names the rows of the admin rule: a fix request of the kind `email`, and a fix request of the kind `partner_warning` whose dry run does not say `simulated` 1 (a dry run that cannot be read is not simulated). `MayApprove` asks it first, keeps the own-address exemption for `email` only, and then holds a `partner_warning` to the same OcuTalonAdmin check as an email (one copy, the roles read at the time of the question). The demo's simulated warning, which goes only to the Simulated mailbox, is not asked, so the demo's "Warn the partner" flow is unchanged. `AnswersIn` uses `AdminRuled` for its `{"kind": "email", "admin": true}` refusal, so every path (web, phone, Telegram) refuses with `answered.notAdmin` ("Only an OcuTalon admin can approve this email."), no new string. `AnswerOps` writes one Action entry for a refused approve of a `partner_warning` (action `partner_warning`, result `refused`, the Ref, the contact ids, user, session, channel; no name, address or text). A reject is never asked.
- DW-1416, what EmailOut's "failed" means for an approved send: the claim of an approval is marked `failed` whatever the failure (`Channel/Email/Out.cls` `Send`: only a keyed tool send is marked `maysent`), so a timeout or a connection lost during DATA is answered `MESSAGEUNREACHABLE` and an error after the claim `MESSAGEFAILED`; neither says the mail server never took the email. `MESSAGEMAYHAVESENT` is that class's own sentence for a keyed send. The refused-before-the-send, refused-login, sign-in, rejected and unavailable sentences say nothing was handed over. `PartnerWarning.MayHaveSent(reason)` is 1 for `MESSAGEMAYHAVESENT`, `MESSAGEUNREACHABLE` and `MESSAGEFAILED` (`MAYHAVESENTSENTENCES`, read from Out with `$Parameter`). Kind `email` has no timeline line for a send (its run ends with `summary.fixEnded`), so there was no wording to reuse. A failed Settings-contact run with such a reason, and a run that a restart cut short (an interrupted request: whether the mail was handed over is not known), end with the new line below; any other failed run keeps `summary.partnerNotSent`; a failed run of the simulated contact never reads "may have been sent". The line holds the time only. A claim that is `failed` is never sent again (`Test.Partner.PartnerMail:TestOneSendPerApproval`).
- DW-1416, FINAL may-have-sent line, key `summary.partnerMaySent` in `src/ocutalon/cls/OcuTalon/Msg/Catalog/Watch.cls`, slot `time`: "{time}: the delay notice may have been sent. Check the mailbox's Sent folder before sending it again."
- shards-11: `OcuTalon.Test.Fix.PartnerMail` and `OcuTalon.Test.Fix.PartnerTurns` moved to `OcuTalon.Test.Partner.*`, with the new `OcuTalon.Test.Partner.PartnerApprove`, in the new lane-a area `Partner` (`shard_areas` in `ci/units.sh`), which runs with the area Docs as the piece `shard:lane-a@Docs,Partner` in shards-7. No limit was changed.

**Extend, don't copy (Rule 2):**
- `For`/`Named` extend the fixture reader in place, through the same `{id, name, address}` shape as `ForProduction`; `Ids` reuses `Joined`.
- `ForApprover` and `Mail` follow the per-kind hook pattern of `Ready`/`Facts`, dispatched like `ForName`; `Fix.Kind.Email.Mail` is the email kind's existing reading of its row, moved out of Out.
- The executor's partner send reuses `Fix.Kind.Email.SubmitApproved` (extracted from `Email.Execute`) and mirrors `SendEmail`'s Finish shape; Out's three methods keep their bodies' structure and only change where the values come from.
- The request keys copy `incident.partnerRequest`'s structure; the sent and failed results reuse `fix.emailSent`/`fix.emailNotSent`.
- The leak scans reuse the 24.2 helpers; `Test.Fix.PartnerMail` reuses `EmailOutProbe` and, where public, `Test.Channel.EmailOut`'s helpers.

**Consumes:** `Data.PartnerContact.ForProduction` (Story 24.2); `SettingsOps.PartnersShown` reads `TABLE` (24.2); EmailOut's system send and claim (Stories 21.6, 21.13; Story 22.7's `Execute` Submit); `Test.Fix.Email`'s SMTP-mock helpers.
**Consumed-by:**
- Story 24.4 (the cards show partner warnings: the recipients through this reader and the stored row; the bands by `simulated`);
- `Channel.Email.Out` (this story; any later mailing kind declares `MAILS` 1 and its `Mail`).

**Ledger inbox (Rule 17):**
- DW-1393 is addressed (Tasks: `PartnerContacts` de-duplication; matrix DEDUPE).
- DW-1394 is addressed (AC1, AC5, AC6; the literal pin and the real e2e state).
- DW-1254's contact-id part is AC3 (now also over the sent path: the `SendEmail` command and its result carry no identity). The ledger entry stays 24.2's.

### Planner rulings, 23.13 re-plan (2026-11-16 ~00:30Z; BINDING; prompts/story-242-rulings-20261115.md "23.13 re-plan")
- Design APPROVED as described (the fictional demo contact refused for a real send; Test.Fix.PartnerMail with six pins, each with a mutation; PartnerTurns covers the full path with a leak scan).
- NEW text APPROVED verbatim: line 1 `incident.partnerRequestMailbox` (phone and web forms) and line 2 `result.partnerSkipped`, exactly as drafted under `### For the Planner's gate`.
- D9 APPROVED: new key `partner.emailSubject` = "Delay notice", no slots; `partner.subject` stays for the simulated case only. PIN: a real send never uses the "Simulated" subject (with a mutation).
- D6, D7, D8 and D10 ACCEPTED. Contention: plain union, flag any overlapping hunks at integrate.

### Planner rulings, 23.13 GATE (2026-11-15 ~23:30Z; BINDING; prompts/story-242-rulings-20261115.md "23.13 GATE")
- APPROVED with ONE CHANGE (veto 2): the send rule in the intent block above (SENT through 21.11's EmailOut when a mailbox is connected; kept as an approved draft ONLY when none is connected; STOP if EmailOut can't carry it).
- Public text APPROVED with conditional wording, verbatim:
  - Phone and web forms of `incident.partnerRequestKept`, the Dry run line: "Dry run: no mailbox is connected in Settings > Channels > Email, so if you approve, the notice is kept as an approved draft and nothing is sent." The rest of the two forms verbatim as proposed.
  - `press.approvedPartnerKept`: "Approved. The delay notice is kept as a draft: no mailbox is connected in Settings > Channels > Email."
  - `APPROVAL_TEXTS.partnerKeptNote`: "Nothing is sent unless you approve. No mailbox is connected in Settings > Channels > Email, so an approved notice is kept as a draft."
  - SENT path: reuse 21.11's approved email texts where they fit; any new line goes to the Planner.
- Vetoes 1, 3, 4 APPROVED (online demo unchanged; trace, logs and audit carry contact ids only; the approval row holds names and addresses until the standard purge). Deviations 1-5 ACCEPTED. The AD-16 bullet (written by the lead with the Planner's marker) includes the sent-or-kept rule.
- Contention: plain union with lane D's 24.4a (`Live/Payload/Incident.cls`, `Watch/IncidentManager.cls`, `Fix/Executor.cls`).

### Planner rulings, "23.13 EmailOut" (2026-11-15 ~23:55Z; BINDING)
- Option (i): this story edits `Channel/Email/Out.cls` (`Authorised`, `ApprovedRecipients`, `Approved`) and adds the `Fix/Executor.cls` branch (plain union with 24.4a). AD-14 amendment approved (spine bullet "EmailOut's system send for fix kinds").
- The approved-address rule and its pins (same address sent; removed skipped; changed skipped; the online-demo refusal for `partner_warning`); one send per approval and count-only logs carry over.
- Texts: the sent result reuses `fix.emailSent`/`fix.emailNotSent`; the no-mailbox request uses `incident.partnerRequestKept`; the two NEW lines go to the Planner before their surfaces are implemented; the rest proceeds meanwhile.

### For the Planner's gate

**(a) Veto items, each with its online-demo behaviour:**
1. **To whom a warning goes** (APPROVED, veto 1). Online demo: unchanged (fixture, simulated, Simulated mailbox; the Settings section hidden, its route 409).
2. **What a Settings-contact warning sends** (CHANGED by the ruling, now planned): one real email per approval from the connected mailbox, only to the addresses stored in the approval row that still match the contacts; kept when no mailbox is connected. A fictional fixture contact is never mailed (`Mail` refuses a fixture production). Online demo: EmailOut answers `not_available` first (pinned for `partner_warning`), and the table is never read there.
3. **Stored data** (APPROVED, veto 3): `to` holds contact ids; the approval row's `DryRun` and the approval live event hold names and addresses until the standard purge; traces, logs and audit hold ids only. The sent path adds one `Data.Delivery` row per sent approval (no address, as for the email kind). Online demo: fixture rows only.
4. **`TABLE = 1`** (APPROVED, veto 4). Online demo: hidden by `SettingsOps`.
5. **EmailOut's recipient rule widened** (AD-14 amendment, APPROVED): a system send is now authorised for any executing row whose kind declares `MAILS` 1; only `email` and `partner_warning` do. No privilege, role or route changes.

**(b) Public text:**
- **NEW — to the Planner before implementing** `incident.partnerRequestMailbox` in `src/ocutalon/cls/OcuTalon/Msg/Catalog/Watch.cls` (slots `production` text, `notice` text):
  - text: "I drafted a delay notice about this incident for the partner contacts set for {production}. Approve sending it?\n\nDry run: if you approve, the notice below is sent once by email from the mailbox connected in Settings > Channels > Email, only to the recipients on the approval card on your OcuTalon page.\n\n{notice}\n\nNothing has been sent yet.\n\nDetails and trace: on your OcuTalon page."
  - web: "I drafted a delay notice about this incident for the partner contacts set for {production}.\n\nDry run: if you approve, the notice below is sent once by email from the mailbox connected in Settings > Channels > Email, only to the recipients on the approval card.\n\n{notice}\n\nNothing has been sent yet.\n\nDetails and trace: on your OcuTalon page."
- **NEW — to the Planner before implementing** `result.partnerSkipped` in `src/ocutalon/cls/OcuTalon/Msg/Catalog/Watch.cls` (slots `sent`, `skipped`, `total`, all count; also listed on the page through `web/scripts/catalog.mjs`): "The delay notice was sent to {sent} of {total} partner contacts. Not sent to {skipped}: they were removed from Settings > Partner contacts, or their address changed, since this request was made."
- **Approved (ruled 23.13 GATE), used as ruled:** `incident.partnerRequestKept` in `Msg/Catalog/Watch.cls`:
  - text: "I drafted a delay notice about this incident for the partner contacts set for {production}. Approve?\n\nDry run: no mailbox is connected in Settings > Channels > Email, so if you approve, the notice is kept as an approved draft and nothing is sent. The recipients are on the approval card on your OcuTalon page.\n\n{notice}\n\nNothing has been sent yet.\n\nDetails and trace: on your OcuTalon page."
  - web: "I drafted a delay notice about this incident for the partner contacts set for {production}.\n\nDry run: no mailbox is connected in Settings > Channels > Email, so if you approve, the notice is kept as an approved draft and nothing is sent.\n\n{notice}\n\nNothing has been sent yet.\n\nDetails and trace: on your OcuTalon page."
  - `press.approvedPartnerKept` in `Msg/Catalog/Core.cls`: "Approved. The delay notice is kept as a draft: no mailbox is connected in Settings > Channels > Email."
- **Approved and reused unchanged:** `fix.emailSent` "The email was sent." and `fix.emailNotSent` "{reason}" (Story 21.11) with EmailOut's approved sentences as the reason; `summary.fixEnded` (Story 23.6); Story 23.5's partner keys (`incident.partnerRequest`, `result.partner*`, `summary.*Partner*`, `partner.subject`, `press.approvedPartner`, the card's `partnerTo`/`partnerNote`/`partnerSent`/`partnerSentSome`/`partnerKept`/`partnerNotSent`) for the fixture and the kept path; the 23.10 contact name; 24.2's `settings.partnersHelp`, `settings.partnersOffOnDemo`, `settings.partnerRemoveConfirm`.
- **Not used:** `APPROVAL_TEXTS.partnerKeptNote` (deviation 6).
- **Not public:** the `SYSTEMNOTE` sentence and the mock B prompt.

**(c) Contended-file overlaps (plain union, minimal):**
- `Channel/Email/Out.cls` (Lane B; ruled option (i)): three methods and their doc paragraphs.
- `Fix/Executor.cls` (Lane D 24.4a): one call in `Run`'s contact branch, two new private methods (`SendPartner`, `MailApproved`), the `ActionTarget` line, doc.
- `Watch/IncidentManager.cls` (Lane D 24.4a): 5 one-line hooks.
- `Watch/Notice.cls`: `AskedKey`/`ResultKey` optional arguments, the new key parameters, one `AskedSlots` branch, three `ResultSlots` cases.
- `Watch/Summary.cls` (Watch/**, Lane D): one line at 190 and its doc line.
- `web/e2e/settings/partner-contacts.spec.ts`: 24.2's test in Lane C's Settings area; the simulation route is dropped.

**(d) Deviations, with recommendations:**
1-5. As accepted at the 23.13 GATE (deviation 1 now reads: Settings contacts never go to the Simulated mailbox; they are mailed for real or kept).
6. **No card note for Settings-contact requests; `APPROVAL_TEXTS.partnerKeptNote` not used.** The card can't tell a connected mailbox from none without a new stored dry-run key (stored data, AD-12's "no new field"); the chat request text carries it. Recommend accept.
7. **No Telegram press text when a mailbox is connected** (the existing empty answer); the result follows as `fix.emailSent`. Recommend accept (no new line).
8. **Summary line of a real send uses the approved `summary.fixEnded`** ("{time}: the fix ended: 0 resent, 2 completed, 0 failed again, 1 skipped."), because `summary.partnerSent` names the Simulated mailbox. Truthful but generic. Recommend accept, or rule a partner line later.
9. **The email's subject needs a ruling: a third outward text the brief did not foresee.** EmailOut requires a subject (1-200 characters), and the only partner subject, `partner.subject` "Simulated delay notice to {recipient}", would be false on a real email. This plan drafts no third NEW line (the brief asked for two); the subject surface is gated with the two NEW lines. Recommendation for the Planner: a fixed key `partner.emailSubject` in `Msg/Catalog/Watch.cls`, "Delay notice", with no slot (it names no production, contact or tool). Until ruled, `PartnerWarning.Mail` and the SENT path are not implemented.
10. **"Since this request was made"** in NEW line 2, not "since approval": the stored addresses are those resolved when the request was raised and shown on the card, which is what the rule compares.

**(e) CI:**
- No `.github/workflows` or `release/**` hunk, and no new unit or group.
- `Test.Fix.PartnerMail` is a new class in `Test/Fix`, picked up by `shard:lane-a@Fix` (shards-11); it adds about 20-40 s (inference). `PartnerTurns` adds about 60-90 s for its two new methods (inference). `Test.Channel.EmailOut` and `Test.Fix.Email` gain no method and stay in their shards.
- Web: the `web` job (`approval-view`, `incident-view`, `catalog` tests); `live:sign-in-2` for `e2e/settings`.

## Verification

Run from the epic-23 worktree root, one command per call with `timeout: 600000`, each sized to about 150 s, and never two test runs in one message.
- Prefix every `ci/` call with `OCUTALON_LOCK_DIR=<main checkout>/.worktrees/.coordination/locks/lane-b OCUTALON_TEST_WEB_PORT=52802 OCUTALON_LOCK_OWNER='epic=23 stage=implement'`.
- Tags: fresh `e23b13i`, warm `e23b13iw`.
- Change `ci/mock/**` before `ci/warm.sh up`.
- At the end, also after a failure, run `ci/warm.sh down`, then `ci/iris.sh teardown` with each tag.

**Shared surfaces:**
- the partner-warning recipients and the `to`/dry-run shape (the `Request` helpers and the row fixtures in `Test.Demo.Guide`, `Test.Eval.Report`, `Test.Live.Payloads`, `Test.Channel.TelegramApproval` and `Test.Fix.Kind`);
- EmailOut's system-send authorisation (`Test.Channel.EmailOut` row helper `Approval`, `Test.Fix.Email` `Seed`): every `email` case must stay green;
- the Settings sections shown (`partner-contacts` is now present off the online demo: S1/S1f, deep-link, on-call, roles and `Test.Core.SettingsSave` 441 follow the real value);
- the product keys `email.address`/`email.owner`/`onlineDemo` that the new tests set (save and restore);
- the leak-scan inputs;
- the catalog key counts, request-key lists (`Test.Msg.Catalog`) and the page catalog list and counts (`web/scripts/catalog.test.mjs`);
- `APPROVAL_TEXTS` keys and the partner bands;
- `SYSTEMNOTE` and the mock B prompt;
- the `Fix.PartnerContacts` and `Fix.Kind` method lists.

Every test added or changed passes on a fresh environment, in either order.

**Commands:**
- (loop) `OCUTALON_RUN_TAG=e23b13iw ci/warm.sh up`; re-up (down, then up) after any change to `ci/mock/**` or the production's Fix, Watch and Channel classes. Then `OCUTALON_WARM=1 OCUTALON_RUN_TAG=e23b13iw ci/iris.sh class <C>`, one call each. Expected: `CLASS ... passed`.
  - `OcuTalon.Test.Fix.PartnerMail`
  - `OcuTalon.Test.Fix.PartnerWarning`
  - `OcuTalon.Test.Fix.PartnerDraft`
  - `OcuTalon.Test.Channel.EmailOut`
  - `OcuTalon.Test.Msg.Catalog`
  - `OcuTalon.Test.Channel.TelegramApproval`
  - `OcuTalon.Test.Fix.PartnerTurns:TestSettingsContactsLeakNothing`
  - `OcuTalon.Test.Fix.PartnerTurns:TestAskedTurnRaisesWithinBounds`
- (loop) `node --test web/scripts/approval-view.test.mjs web/scripts/incident-view.test.mjs web/scripts/catalog.test.mjs` -- expected: pass.
- (loop) `bash docker/tests/test-mock.sh` -- expected: pass.
- (once) On the warm stack, one call each: `OcuTalon.Test.Fix.PartnerTurns` methods `TestApprovedNoticeIsSentByteForByte`, `TestDemoModeOffKeepsTheNotice`, `TestInjectedTurn`, `TestSecondSessionAsks` and `TestResolvedDraftSaysTheOrdersWentThrough`; then the classes `OcuTalon.Test.Core.SettingsPartners`, `OcuTalon.Test.Core.SettingsSave`, `OcuTalon.Test.Web.PartnerSettingsApi`, `OcuTalon.Test.Live.Payloads`, `OcuTalon.Test.Fix.Kind`, `OcuTalon.Test.Demo.Guide` and `OcuTalon.Test.Eval.Report`. Expected: passed.
- (once) Fresh stack `e23b13i`, one call each: `ci/iris.sh class OcuTalon.Test.Fix.PartnerTurns:TestSettingsContactsSentOnce`; `ci/iris.sh class OcuTalon.Test.Fix.PartnerTurns:TestSettingsContactsLeakNothing`; `OcuTalon.Test.Fix.Email` methods `TestSeededApprovedRowSendsOnce`, `TestSystemSendTakesItsSubjectAndTextFromTheRow`, `TestEmptyRecipientsOfASystemSend`, `TestOnlineDemoSendsNothing`, `TestSendFailuresEndFailedOnce` (one per call). Expected: passed.
- (once) `npm --prefix web test` -- expected: pass.
- (once) `OCUTALON_RUN_TAG=e23b13i ci/iris.sh build`, then `OCUTALON_RUN_TAG=e23b13i ci/iris.sh live sign-in-2 --part k/N` for the part that holds `settings/partner-contacts.spec.ts`. Find k/N with `npm --silent --prefix web run e2e:sign-in-2 -- --list --reporter=json` and `node web/scripts/e2e-part.mjs`, choosing N so that the part ends inside about 150 s. Expected: passed.
- (once) Each script of `CHECK_SCRIPTS` in `ci/units.sh` as `bash docker/tests/test-<name>.sh`, one per call -- expected: each passes.
- Left to CI: the shards (`lane-a@Fix` in shards-11, `lane-a@Channel`, lane-b), the other browser units, the rest of `Test.Fix.Email`, and the lead's fresh-environment check, forward and `--reverse`.

**Mutations (Rule 19), one per AC and per ruled pin, each recorded as `mutation: <change> -> <test red>`:**
- AC1: remove `TABLE` -> the PartnerWarning literal pin, and e2e P1.
- AC2: drop the namespace match or the de-duplication in `For` -> PartnerWarning DEDUPE/OTHER_SCOPE.
- AC3: put the name back into `Facts`, or an address into the `SendEmail` command -> `PartnerTurns:TestSettingsContactsLeakNothing` / `TestSettingsContactsSentOnce`.
- AC4: `ForApprover` returns the ids unchanged -> PartnerDraft's row/card assertion.
- AC5 / pin "same address sent": `Mailed` keeps the `FixKind` `email` gate (Out refuses `partner_warning`) -> `PartnerMail:TestSameAddressIsSent`.
- AC5 / one send: `SendClaimed` skipped for a partner row -> `PartnerMail:TestOneSendPerApproval`.
- AC6: `Ready` gives 1 with no mailbox -> PartnerWarning KEPT.
- AC7 / pin "removed skipped": `Mail` sends to a stored address without checking `For` -> `PartnerMail:TestRemovedContactIsSkipped`.
- AC7 / pin "changed skipped": `Mail` sends to the current address -> `PartnerMail:TestChangedAddressIsSkipped`.
- AC8 / pin "online-demo refusal": move `Handle`'s online-demo line below `Authorised` and let `Mail` ignore the flag -> `PartnerMail:TestOnlineDemoRefusesPartnerWarning`; `Simulated` gives 0 for the Orders production -> `PartnerTurns:TestApprovedNoticeIsSentByteForByte` and `PartnerMail:TestFixtureIsNeverMailed`.
- AC9: `Email.Mail` returns the recipients in reverse or lower-cased -> `Test.Channel.EmailOut:TestSystemApproval` / `Test.Fix.Email:TestSeededApprovedRowSendsOnce`.
- AC10: `IncidentManager` keeps `For(incident.Production)` with no namespace -> `PartnerTurns:TestSettingsContactsLeakNothing` (no request).

Observed in the implement stage (warm stack `e23b13iw`; each change reverted, `git diff --stat` unchanged, the class green again afterwards):
- mutation: `Parameter TABLE;` (AC1) -> `PartnerWarning:TestTableSwitch` red.
- mutation: the `$Data(seen(key))` line of `For` removed (AC2) -> `PartnerWarning:TestSettingsContactsOfAProduction` red.
- mutation: `Facts` with the "Partner:" line back (AC3) -> `PartnerWarning:TestFacts` red.
- mutation: `ForApprover` quits with the ids unchanged (AC4) -> `PartnerDraft:TestSettingsContactsDraft` red.
- mutation: `Mailed` keeps the `email` gate (AC5, same address sent) -> `PartnerMail:TestSameAddressIsSent` red.
- mutation: Out's system send calls `Send` instead of `SendClaimed` (AC5, one send) -> `PartnerMail:TestOneSendPerApproval` red.
- mutation: `Ready` gives 1 with no mailbox (AC6) -> `PartnerWarning:TestSettingsContactsKeptWithoutAMailbox` red.
- mutation: `Mail` sends the stored address without asking `For` (AC7, removed) -> `PartnerMail:TestRemovedContactIsSkipped` red.
- mutation: `Mail` sends the current address (AC7, changed) -> `PartnerMail:TestChangedAddressIsSkipped` red.
- mutation: Out's online-demo line removed (AC8, refusal) -> `PartnerMail:TestOnlineDemoRefusesPartnerWarning` red.
- mutation: `Simulated` gives 0 for the Orders production (AC8, fixture) -> `PartnerMail:TestFixtureIsNeverMailed` red.
- mutation: `Email.Mail` gives no recipient (AC9) -> `Test.Channel.EmailOut` (`TestBadValues`, `TestClaimIsLocked`) red; the reversed order is not caught by `Test.Channel.EmailOut` (it compares the recipients as a set).
- mutation: `Email.Mail` returns the recipients in reverse order (AC9) -> `Test.Fix.Email:TestSeededApprovedRowSendsOnce` red (and `Test.Channel.EmailOut` stays green).
- mutation: `IncidentManager.AskedDraft` keeps `For(incident.Production)` (AC10) -> `PartnerDraft:TestSettingsContactsDraft` red.
- mutation: `Email.SubmitApproved` puts the row's recipient addresses into the `SendEmail` command (AC3, leak) -> `PartnerTurns:TestSettingsContactsSentOnce` red.
- mutation: `IncidentManager.ResultNotice` passes simulated 1 to `Notice.ResultKey` (AC5, the session reads `fix.emailSent`) -> `PartnerTurns:TestSettingsContactsSentOnce` red.
- mutation: `Summary.RunEvents` treats every run as simulated (AC5, `summary.fixEnded` for a real send) -> `Test.Watch.Summary` red.
- mutation: `Telegram.In.PressText` drops the connected-mailbox quit (AC6, the press text) -> `Test.Channel.TelegramApproval` red.
- mutation: `Executor.SendPartner` without its `'mailed` could-not-start branch (TAMPERED, the run's state and reason) -> `PartnerWarning:TestSettingsContactsTamperedRowCouldNotStart` red.
- mutation: `incident-card.ts` context without `approvals` (the compact card's band reads simulated from the stored approvals) -> `web/scripts/approval-sources.test.mjs` red.

QA stage (2026-11-15, warm stack `e23b13q`; each change reverted, `git status --short` empty afterwards, the class green again) (QA). No test file was added; the pins below already existed and had no recorded mutation:
- mutation: `PartnerWarning.Mail` takes a "Simulated delay notice" subject instead of `partner.emailSubject` (a real send never uses the Simulated subject) -> `PartnerMail:TestSameAddressIsSent` red ("and the subject Delay notice", "which is never the Simulated subject of the demo's notice").
- mutation: `PartnerContacts.For` without its `OnlineDemo()` quit (ONLINE_DEMO_TABLE) -> `PartnerWarning:TestSourceFollowsTheProduction` red.
- mutation: `PartnerWarning.Plan` without its `Simulated` condition (EXECUTE_GUARD) -> `PartnerWarning:TestSettingsContactsExecuteGuard` red.
- mutation: `Fix.Kind.Mailed` without its `State "executing"` condition (nothing is sent before approval) -> `PartnerMail:TestTamperedRowIsRefused` red.
- mutation: `Notice.ResultKey` never reads `result.partnerSkipped` (AC7, the session) -> `PartnerWarning:TestSettingsContactsSkipped` red.
- mutation: `PartnerWarning.Facts` names the first Settings contact (AC3, a name in the draft input) -> `PartnerTurns:TestSettingsContactsLeakNothing` red ("is in no trace body, header or log table").
- mutation: `approval-view.ts` shows a sent band when `simulated` is unknown (AC7, web) -> `web/scripts/approval-view.test.mjs` red ("shows no sent band when it cannot tell").
- mutation: `approval-view.ts` never reads the skipped band (AC7, web) -> `web/scripts/approval-view.test.mjs` red ("reads the bands of a request that is not simulated from the email results").
- mutation: `Parameter TABLE;` (AC1, DW-1394, the real page) -> `web/e2e/settings/partner-contacts.spec.ts` P1 red (live sign-in-2 part 12/14, fresh stack).
- Code review stage (2026-11-15; change reverted from a backup, `git diff` of the file unchanged afterwards, the test green again): mutation: `chat-panel.ts` `announce` builds `incidentContext` without `this.live.store()?.approvals` (AC8, the demo's sent band is announced in the chat) -> `web/scripts/approval-sources.test.mjs` red ("announces the result bands with the live store's approvals"). After the review patches, on the warm stack `e23b13crw`: `Fix.PartnerWarning`, `Fix.PartnerMail`, `Fix.PartnerDraft`, `Channel.TelegramApproval`, `Channel.EmailOut`, `PartnerTurns:TestSettingsContactsLeakNothing` and `PartnerTurns:TestSettingsContactsSentOnce` passed; `npm --prefix web test` passed (2158).
- QA runs, all passed: warm `Fix.PartnerMail`, `PartnerWarning`, `PartnerDraft`, `PartnerTurns` (whole, 156 s), `Fix.Email`, `Channel.EmailOut`, `Channel.TelegramApproval`, `Channel.TelegramChat`, `Msg.Catalog`, `Watch.Summary`, `Fix.Kind`, `Core.SettingsPartners`, `Core.SettingsSave`, `Web.PartnerSettingsApi`, `Live.Payloads`, `Demo.Guide`, `Eval.Report`; `npm --prefix web test` (2157); fresh `live sign-in-2 --part 12/14` (9 of 9) and `live cards` (32 of 32).

Rework iteration 1 (2026-11-16; warm stack `e23b13r1w`, fresh stack `e23b13r1`; each change reverted from a backup, `git status --short` and `git diff --stat` unchanged afterwards, the class green again). Production hosts load recompiled classes only after a restart, so the mutations of `Core/AnswerOps.cls` were run with the warm stack's production restarted after the change and again after the revert.
- mutation: `Email.AdminRuled` gives 0 for a partner_warning (the rule does not ask it; DW-1415, every path) -> `Test.Partner.PartnerApprove` red (`TestNonAdminCannotApproveOnTelegram`, `TestNonAdminCannotApproveOnTheWebAndPhoneRoutes`, `TestMayApproveRowByRow`).
- mutation: `AnswersIn` names the admin refusal only for an email approve (the non-admin's refusal reads the plain approver sentence, not email's existing one; DW-1415, Telegram and web/phone) -> `PartnerApprove:TestNonAdminCannotApproveOnTelegram`, `TestNonAdminCannotApproveOnTheWebAndPhoneRoutes` and `TestRoleRevokedBeforeTheApprovalIsRefused` red.
- mutation: `AnswerOps` asks no `MayApprove` (`If $IsObject(row) && 0`; AnswerOps itself and the phone and web channel, with the production restarted) -> `PartnerApprove:TestNonAdminCannotApproveOnTelegram`, `TestNonAdminCannotApproveOnTheWebAndPhoneRoutes` and `TestRefusalIsAuditedWithIdsOnly` red.
- mutation: an admin is refused a partner warning (`MayApprove` gives 0 for it; DW-1415, an admin can) -> `PartnerApprove:TestAdminCanApprove` (web, phone and Telegram), `TestMayApproveRowByRow` and `TestRoleRevokedBeforeTheApprovalIsRefused` red.
- mutation: `MayApprove` keeps the admin role of a user named "revoked" after the role was taken away (DW-1415, a role revoked between the request and the approval) -> `PartnerApprove:TestRoleRevokedBeforeTheApprovalIsRefused` red, and only it.
- mutation: `AnswerOps` without its `AuditRefused` call (DW-1415, the audit entry; production restarted) -> `PartnerApprove:TestRefusalIsAuditedWithIdsOnly` red (telegram, phone and web).
- mutation: `AuditRefused` puts the row's dry run into the entry's target (DW-1415, ids only; production restarted) -> `PartnerApprove:TestRefusalIsAuditedWithIdsOnly` red.
- mutation: `AnswerOps` asks `MayApprove` for a reject too (`If 1`; DW-1415, deny unchanged; production restarted) -> `PartnerApprove:TestDenyIsUnchanged` red.
- mutation: `AdminRuled` asks the simulated warning too (`Quit 1`; the demo's flow) -> `PartnerApprove:TestSimulatedWarningIsApprovedByAnyApprover` and `TestMayApproveRowByRow` red.
- mutation: `Summary.RunEvents` never chooses `summary.partnerMaySent` (DW-1416, may have sent) -> `Test.Watch.Summary:TestSettingsContactMayHaveSent` red.
- mutation: `PartnerWarning` `MAYHAVESENTSENTENCES` without `MESSAGEUNREACHABLE` (DW-1416, a timeout during DATA) -> `Test.Watch.Summary:TestSettingsContactMayHaveSent` red.
- mutation: `MAYHAVESENTSENTENCES` with `MESSAGEREJECTED` added (DW-1416, "failed" that is definitely not sent) -> `Test.Fix.PartnerWarning:TestMayHaveSent` red.
- mutation: `Summary.RunEvents` without its `+run.Interrupted > 0` clause (DW-1416, a run cut short by a restart) -> `Test.Watch.Summary:TestSettingsContactMayHaveSent` red.
- mutation: `MAYHAVESENTSENTENCES` with `MESSAGEREJECTED` in place of `MESSAGEUNREACHABLE` (DW-1416, each reason has its own line; the counts alone stayed green) -> `Test.Watch.Summary:TestSettingsContactMayHaveSent` red (its ordered-line assertion).
- mutation: `Summary.RunEvents` without its `Simulated` condition (DW-1416, the simulated contact is never "may have been sent") -> `Test.Watch.Summary:TestSettingsContactMayHaveSent` red.
- mutation: the sent run of a Settings contact ends with `summary.partnerMaySent` instead of `summary.fixEnded` (DW-1416, sent) -> `Test.Watch.Summary:TestSettingsContactMayHaveSent` red.
- mutation: the catalog text of `summary.partnerMaySent` without its second sentence (DW-1416, the final line) -> `Test.Msg.Catalog` red (`TestEveryKeyOnEveryChannel`, `TestLocalInstallEveryKey`).
- mutation: `PartnerWarning.Mail` sends a stored address whose contact's address changed (the moved `Test.Partner.PartnerMail`, shards-11) -> `Test.Partner.PartnerMail:TestChangedAddressIsSkipped` and `TestAllSkippedSendsNothing` red.
- Runs after the change, all passed: warm `Test.Partner.PartnerApprove` (31 s), `Test.Watch.Summary`, `Test.Fix.PartnerWarning`, `Test.Partner.PartnerMail` (0.3 s), `Test.Partner.PartnerTurns:TestSettingsContactsLeakNothing`, `Test.Msg.Catalog`, `Test.Core.AnswersInProduction`, `Test.Core.AnswersTelegramProduction`, `Test.Fix.EmailRoute`; fresh `Test.Fix.Email:TestOnlyAnAdminApprovesAnEmailToAnotherAddress` and `Test.Partner.PartnerTurns:TestSettingsContactsSentOnce`; `bash docker/tests/test-ci-config.sh` and `bash docker/tests/test-boundaries.sh`; `node --test web/scripts/catalog.test.mjs`. No web code changed.
- shards-11: measured on run 43794653657 (job iris (shards-11), 02:51:27Z to 03:22:45Z, 31 min 18 s): `shard:lane-a@Fix` 1,377 s with its stack's start, `live:cards` 459 s; `Test.Fix.PartnerTurns` 158 s, `Test.Fix.PartnerMail` 1.0 s, `Test.Fix.Waits` 122 s. `ci/iris.sh classes lane-a@Fix` no longer lists them (28 classes), and `ci/iris.sh classes lane-a@Docs,Partner` (the piece of shards-7) lists `Test.Partner.PartnerApprove`, `PartnerMail` and `PartnerTurns`. Planned (inference until a run measures them): shards-11 about 28.7 min, shards-7 about 26.7 min (23.5 min measured).
Code review stage, rework iteration 1 (2026-11-16; warm stack `e23b13cr2w`, fresh stacks `e23b13cr2`; each change reverted from a backup, `git diff --stat` unchanged afterwards, the test green again):
- mutation: `Summary.RunEvents` lets `+run.Interrupted > 0` choose `summary.partnerMaySent` outside its `Simulated` guard (DW-1416, a cut-short run of the demo's simulated contact is never "may have been sent") -> `Test.Watch.Summary:TestSettingsContactMayHaveSent` red ("a failed run and a cut-short run of the simulated contact end with summary.partnerNotSent").
- mutation: `Email.AdminRuled` gives 0 for a partner_warning (`If 1 Quit 0`; DW-1415, the web refusal over real HTTP) -> `web/e2e/api/approver.spec.ts` AP6 red (200 instead of 403; live sign-in part 2/30, fresh stack).
- Runs, all passed: warm `Test.Partner.PartnerApprove` (31.9 s), `Test.Watch.Summary` (6.9 s), `Test.Fix.PartnerWarning` (4.0 s), `Test.Fix.Email` (34.5 s), `Test.Core.AnswerPrecedentsProduction` (26.7 s); fresh `ci/iris.sh live sign-in --part 2/30` (`api/approver.spec.ts`, AP1 to AP6, 6 passed); `bash docker/tests/test-ci-config.sh` all rules passed; `npm --prefix web test` 2173 passed. `ci/iris.sh classes lane-a@Docs,Partner` lists the three `Test.Partner` classes and `lane-a@Fix` none of them.

## Auto Run Result

Status: done
Blocking condition: none

Rework iteration 1 (2026-11-16), from baseline dbc68f1d4: DW-1415, DW-1416 and the shards-11 rebalance, each ticked under Tasks & Acceptance. This pass covers only those three items.

**Summary.** DW-1415: `Fix.Kind.Email.MayApprove` now also holds a non-simulated partner warning to the OcuTalonAdmin check (`AdminRuled`), enforced in `AnswerOps` for web, phone and Telegram with email's existing refusal text; a refused approve sends nothing, keeps no draft and writes one ids-only audit entry; deny is unchanged. DW-1416: a Settings-contact run that failed with an EmailOut sentence that does not say the mail was never handed over, or that a restart cut short, ends with the new timeline line `summary.partnerMaySent`; the three answers are pinned. shards-11: `PartnerTurns`, `PartnerMail` and the new `PartnerApprove` run as `Test.Partner.*` in shards-7 (`shard:lane-a@Docs,Partner`); no limit changed.

**Review (rework 1).** 21 findings: 1 medium patched (an interrupted run read "not sent"), 3 low patched (a wrong shard in Design Notes, the `ci/units.sh` comment, the Summary test's per-reason pin), 17 rejected with reasons in the Review Triage Log. Nothing deferred. Follow-up review recommended: false (no high patched).

**Verification (rework 1).** Warm stack: `Test.Partner.PartnerApprove`, `Test.Watch.Summary` (after the patch, with both mutations red then green), `Test.Fix.PartnerWarning`, `Test.Partner.PartnerMail`, `Test.Msg.Catalog`, `Test.Fix.EmailRoute`, `Test.Core.AnswersIn` and the implement runs above; fresh: `Test.Fix.Email:TestOnlyAnAdminApprovesAnEmailToAnotherAddress`, `Test.Partner.PartnerTurns:TestSettingsContactsSentOnce`. `bash docker/tests/test-ci-config.sh` and `bash docker/tests/test-boundaries.sh` pass. No web code changed.

Earlier pass: implement and review pass (2026-11-15), from baseline 3d5b7145d.

**Rework iteration 1 files (2026-11-16).** DW-1415: `Fix/Kind/Email.cls` (`AdminRuled`, `MayApprove`), `Core/AnswersIn.cls`, `Core/AnswerOps.cls` (the two Lane B-area classes already carry the email rule; one call and one audit method), new `Test/Partner/PartnerApprove.cls`. DW-1416: `Fix/Kind/PartnerWarning.cls` (`MAYHAVESENTSENTENCES`, `MayHaveSent`), `Watch/Summary.cls`, `Msg/Catalog/Watch.cls` (`summary.partnerMaySent`), `Test/Msg/Catalog.cls`, `Test/Watch/Summary.cls`, `Test/Fix/PartnerWarning.cls`. shards-11: `ci/units.sh`, and the moves `Test/Fix/PartnerMail.cls` and `Test/Fix/PartnerTurns.cls` to `Test/Partner/` (one doc word in `Test/Fix/Email.cls`). `PartnerApprove` sits in `Test/Partner/` so that it does not add to shards-11. This spec is shared.

**Summary.** Partner warnings go to the Settings contacts. `Fix.PartnerContacts` declares `TABLE = 1` and chooses its source by production (the Orders fixture while demo mode is on, else the de-duplicated Settings contacts, never read on the online demo). Every traced message names contacts by id; `ForApprover` writes names and addresses into the approval row only. An approved request of a Settings contact is sent by one system `SendEmail` through EmailOut (AD-14 amended: `Fix.Kind` `MAILS`/`Mail`/`Mailed`, `Email.Mail`, `PartnerWarning.Mail` with the approved-address rule, `Out` `Approved`/`ApprovedRecipients`/`Authorised` read through `Mailed`, the executor's `SendPartner`/`MailApproved`) when a mailbox is connected, else kept as the approved draft. The texts are the Planner's, verbatim.

**Files changed.** Product: `Fix/PartnerContacts.cls`, `Fix/Kind.cls`, `Fix/Kind/PartnerWarning.cls`, `Fix/Kind/Email.cls`, `Fix/Executor.cls`, `Channel/Email/Out.cls` (the three ruled methods), `Channel/Telegram/In.cls`, `Watch/IncidentManager.cls`, `Watch/Notice.cls`, `Watch/Summary.cls`, `Msg/Catalog/Core.cls`, `Msg/Catalog/Watch.cls`, `ci/mock/scenarios/B/partner-notice-draft.json`; web: `approval-view.ts`, `approval-request-card.ts`, `incident-card.ts`, `incident-view.ts`, `msg/catalog.ts` and `scripts/catalog.mjs`. Tests: new `Test.Fix.PartnerMail`, `Test.Fix.PartnerSupport`; changed `Test.Fix.PartnerWarning`, `PartnerTurns`, `PartnerDraft`, `Email`, `ExecutorProbe`, `Test.Channel.TelegramApproval`, `TelegramChat`, `Test.Msg.Catalog`, `Test.Watch.Summary`, web `approval-sources`, `approval-view`, `incident-view`, `catalog`, `ux-strings` tests and the e2e `settings/partner-contacts.spec.ts` (the real `TABLE = 1`, no simulated route).

**Review.** 36 findings from the four layers: 2 medium patched (the executor's could-not-start branch, and the web wiring of `simulated`, both now pinned by a test with a demonstrated mutation), 1 low patched (the missing mutation lines, now recorded), 33 rejected with their reasons in the Review Triage Log (11 false, 22 low). Nothing deferred.

**Follow-up review recommended: true.** Two mediums were patched; both are test additions only (no product code changed after the layers read the diff). The risk to look at again is `PartnerWarning:TestSettingsContactsTamperedRowCouldNotStart` and the two source pins in `web/scripts/approval-sources.test.mjs`, which were reviewed only by the lead.

**Verification performed.** Warm stack: `PartnerMail`, `PartnerWarning`, `PartnerDraft`, `Channel.EmailOut`, `Msg.Catalog`, `Channel.TelegramApproval`, `PartnerTurns` (all five listed methods and the two leak and bounds methods), `Core.SettingsPartners`, `Core.SettingsSave`, `Web.PartnerSettingsApi`, `Live.Payloads`, `Fix.Kind`, `Demo.Guide`, `Eval.Report` passed. Fresh stack: `Fix.Email` and the whole `PartnerTurns` (158 s, with the real SMTP mock) passed. `node --test` of the three web view tests (226) and `npm --prefix web test` (2157) pass; `docker/tests/test-mock.sh` and `bash ci/checks.sh` (33 scripts, including `test-boundaries.sh`) pass; `ci/iris.sh live sign-in-2 --part 12/14` passes 9 of 9. Initial web bundle: 895,477 bytes of JS and CSS referenced by index.html, under the 1 MB cap. Left to CI: the shards (`lane-a@Fix`, `lane-a@Channel`, lane-b), the other browser units and the fresh-environment check forward and reverse.

**Residual risks.** `Fix.Kind.Email.Mail` and `Out.Approved` treat an empty subject or text of a row as not held (reviewers' blind 1). The ask-time key (kept or mailbox) is chosen when the request is raised and the mailbox can change before the approval (blind 2). `Notice.AskedKey(kind)` with no dry run still returns `incident.partnerRequest` (Design Notes, Decided in-stage).
