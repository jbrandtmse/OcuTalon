---
title: 'Story 23.5: Draft partner delay notices that are sent only after approval'
type: 'feature'
created: '2026-11-09'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-23-context.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-23-2-suspend-resume-and-reroute-with-a-dry-run.md'
warnings: [oversized]
deferred: []
---

<intent-contract>

## Intent

**Problem:** When an incident delays a partner's flow, nothing tells the partner. A user can't ask OcuTalon to warn them, and a judge on the online demo has no way to see a drafted notice that goes out only after the user approves its exact text and recipients.

**Approach:** A new fix kind, `partner_warning`, asked for in the chat through 23.2's `propose_fix`. `IncidentManager` has the notice drafted through `Decide` from code-built facts only (count, times, affected flow, plain cause), as an untrusted turn with no actions, following Digest's summary request. It then raises one `fix` request whose dry run holds the exact text and every recipient. Recipients come from a read-only, demo-only partner-contact fixture. After approval, `FixExecutor` re-checks the recipients and sends the approved text byte for byte to the session's Simulated mailbox through `SimMailboxOut`. With demo mode off it keeps the approved notice as a draft and says why.

## Boundaries & Constraints

**Always:**
- Nothing is sent without an approved row. The executor reads the kind, text and recipients only from the row (AD-16) and re-checks every recipient against the fixture before sending.
- The draft's input is built by code from the incident's count, item noun, first and last failure times, production, failed item(s), the stored plain cause and the fixture's partner names. It never includes a message body, sample error, setting value or evidence. The draft request is `Kind` turn, `Provenance` untrusted and `SessionMode` fresh, so the gate lets it act on nothing (`Bridge/Policy/Gate.cls:169`).
- The chat tool only submits a command (AD-1). `propose_fix` keeps its 23.2 classification (`safe`, not read-only), so the gate denies it in an untrusted or tainted turn. A partner warning takes no item, address or other parameter from the chat.
- Every public text says that the notice went to the Simulated mailbox, or that it is kept as a draft. No text says or implies that a real email was sent.
- A partner-warning request never moves the incident's state (Design Notes, AD-15 note). It is told to the sessions, answered and carried out in any state but `closed`.
- Producers never render (AD-32): every fixed text is a catalog key. The notice body is the approved model text, stored and shown verbatim and never rendered as a catalog template.
- On the online demo, a partner warning is drafted only while the session is within the 20 simulated emails an hour (owner-fixed (8)). Sent notices count toward that limit.

**Never:**
- No `EmailOut` and no real email. No partner-contact table, no write path for contacts, and no dependency on Epics 21, 24 or 36 or Stories 23.3, 23.4, 23.7 or 23.8.
- No new `/api/v1` route, table, column, live-event type, role, resource or grant.
- No automatic draft when a notice is built (Design Notes). The guide's five steps and its incident are unchanged.
- No edit of 23.2's or 23.6's specs, and nothing under `irislib/` or `irissys/`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Ask | Demo mode on. The session's guide incident is `resolved` (50 orders at `OrdersFromPartner`). `propose_fix {kind: partner_warning}` | Tool outcome `drafting`. One async `Watch.Msg.Draft` is started, and one Decide turn runs with the facts input. Incident state unchanged | No error expected |
| Draft raised | Decide answers with text T | T is normalised (one paragraph, at most `NOTICEMAX` 1000 characters). One `fix` request is raised: FixKind `partner_warning`, FixParameters `{text: T, to: "it@results-partner.example"}`, FixTargets `1`, DryRun `{notice: T, recipients: [{name, address}], simulated: 1}`. It is added to `RequestRefs` with one `approval` notification `incident.partnerRequest`. State unchanged | No error expected |
| Approved | Request approved, demo mode on | Recheck passes contact 1. One `Fix.Msg.PartnerNotice` goes to `SimMailboxOut`, which saves a SimMessage (out, Sender OcuTalon, Subject from `partner.subject`, `Text` = T byte for byte, ApprovalRef) and publishes one `mailbox` event. FixResult Total 1, Completed 1, Resent 0. `result.partnerSent`, and one Action audit entry. State unchanged | No error expected |
| Demo mode off at run | Approved, `demo.mode` now 0 | Could not start with the kind's `NOTSETUP` reason. The row ends failed with its DryRun text kept, and no SimMessage is written. `result.partnerKept` | Plain line, never silent |
| Recipient gone | Contact id no longer in the fixture, or its address differs from `to` | That recipient is skipped and reported (`result.partnerSentSome` or `result.partnerNotSent`), and never sent to | Reported |
| No contacts | Demo mode off (fixture empty) or a production with no contact | Outcome `refused` with `NOCONTACTS`. Nothing is drafted | Plain reason |
| Item or address given | `propose_fix {kind: partner_warning, item: "x@y"}` | `refused` with `NOITEM`. Nothing is drafted | Plain reason |
| Injected email | An email (untrusted turn) asks to add an address and warn the partner | The gate denies `propose_fix` (`UNTRUSTED`). No draft, no request, no SimMessage to any address. Fixture unchanged | Denied |
| Tampered row | Approved row whose `to`/targets name an address or id the fixture lacks | DryRun refuses it at raise. At run, Recheck skips it. The address is never used | Skipped |
| Already asked | A pending or approved `partner_warning` of the incident exists, or one is raised while a second draft is in flight | `already_asked` at ask. A late second draft raises nothing (one Type 4 line) | No second request |
| Allowance used | Online demo, session at 20 simulated emails (incoming + notices) in the hour | `refused` with `ALLOWANCE`. Nothing is drafted | Plain reason |
| Draft fails | Decide fallback, error, empty or over-long text | Nothing is raised. One `result` notification `result.partnerNotDrafted` (no ApprovalRef) goes to the recipients | Plain line |
| Rejected / expired | Request rejected or expired | Nothing is sent. `answered.rejected`/`answered.expired` is sent and the row records it. State unchanged | Existing notices |
| No approved row | `Execute` for a pending, rejected, unknown or non-fix Ref | Nothing is written or sent. One Type 4 line | Existing refusal |
| Closed incident | Ask on a closed incident | `not_found` (23.2's `Asked`) | Plain reason |

</intent-contract>

## Code Map

- `src/ocutalon/cls/OcuTalon/Fix/Kind.cls` -- contract header 1-18, `KINDS` 35, `ForName` 64, `CheckParameters` 86-102, `DryRun`/`Recheck`/`Execute` 106-128. 23.2 (planned) adds `TARGETTYPE`, `DIAGNOSED`, `ASKED`, `NOSTART`, `NOREAD` and the item-kind result mapping. This story adds `TARGETTYPE` "contact" and the params `DRAFTED`, `MOVES` and `NOTSETUP`, plus a `Ready` hook.
- `src/ocutalon/cls/OcuTalon/Fix/Executor.cls` -- header 1-60 (refusal order, `Finish`, could-not-start rows). `Execute` 199, `Unusable`/`AscendingIds` 262-291 (targets are positive ascending ids, so contact ids fit), `Missing` 295 (empty `RESOURCES` means nothing missing: `Gate.MissingOf` 372-374), `Run` 316-385 (copies, `Wait`, `Finish`; `NotRunning` 330), `CouldNotStart` 411, `Finish` 442, `ActionEntry` 574, `Check`/`Carry` 888-897. 23.2 renames the switching method to `InProduction` and adds the item-kind ending through `Finish`.
- `src/ocutalon/cls/OcuTalon/Watch/IncidentManager.cls` -- `OnRequest` 247-258, `OnResponse` 265-283 (Settle-only today), `OnError` 288-305, `Start` 458-467 (async self-send: the sibling for `Draft`), `SendDiagnose` 705, `Proposed` 891-975 (raise shape), `StoredDryRun` 976, `Notification` 1048, `Move` 1063-1078, `Apply` 1084-1101, `Facts` 1130-1149 (counts other requests as pending or waiting), `Owns` 1151, `Execute` 1167, `Outcome` 1259-1269, `AnswerNotice` 1273, `Compose` 1289, `Result` 1302-1314, `ResultNotice` 1317, `Event` 1337, `Tell` 1423. 23.2 (planned) adds `Asked(command, .response)`, `RaiseFix` and the `ProposeFix` route.
- `src/ocutalon/cls/OcuTalon/Digest/Process.cls` -- the sibling draft request: `SYSTEMNOTE`/`CHANNEL` 112-118, `OnResponse` 167-199 (Reply, Fallback, cut), `SummaryRequest` 556-578, `SendSummary` 862-867.
- `src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls` -- `RUNNERS` 142 (turn -> ChatAgent, pool 1: `Production.cls:35`), timer 145-148/236, one decision per ItemId+Kind (doc 12-13, `OnRequest` 328). `Bridge/Msg/Request.cls` fields 9-62.
- `src/ocutalon/cls/OcuTalon/Tools/RecentActivity.cls` `Entry` 152-187 -- the trusted facts and their display (`CommandCall.TimeLabel` `CommandCall.cls:78`, `WatchAnswers.WatchNames` `WatchAnswers.cls:179`, `FailureGroup.OfIncident`). `Data/Incident.cls`: `Count` 30, `FirstAt` 36, `LastAt` 39, `Cause` 45, `Production` 18, `RequestRefs` 81.
- `src/ocutalon/cls/OcuTalon/Channel/SimMailbox/Out.cls` -- `MessageMap` (Outbound only), `OnOutbound` (Render or Text, SimMessage out, `Keep`, `Announce`). `Channel/Operation.cls` `IsSession` 15, `Announce` 25, `Keep(message, channel, approvalRef, kind, decisionRef, .row)` 38. `Data/SimMessage.cls` `ApprovalRef` 41 (doc: phone rows only today), `Text` 32, `Subject` 38.
- `src/ocutalon/cls/OcuTalon/Core/Allowance.cls` -- `EMAILLIMIT` 28, `MailAllowed` 233-247 (incoming only). `Data/Ownership.cls` `IncomingMail` 664-675. `Channel/SimMailbox/In.cls:116` is the only caller.
- `src/ocutalon/cls/OcuTalon/Demo/Guide.cls` -- `DemoOn` 188. Finish (111-114) reads the incident state only, so a request that does not move the state keeps the guide finished.
- `src/ocutalon/cls/OcuTalon/Watch/Notice.cls` -- `ResultKey` 278, `ResultSlots` 294, `Noun` 360 (23.2 adds the kind argument). `Watch/Summary.cls` `Build` 41, `Text` 122.
- `src/bridge/cls/OcuTalon/Bridge/Data/ApprovalRequest.cls:9` `DRYRUNKEYS`. `src/bridge/cls/OcuTalon/Bridge/Approval.cls:221-231` fix shape check (non-empty targets, JSON dry run).
- `src/ocutalon/cls/OcuTalon/Channel/Telegram/In.cls:451` `PressText`. The `press.` keys live in `Msg/Catalog/Core.cls` (AD-32 prefix rule).
- `src/ocutalon/cls/OcuTalon/Live/Payload/Approval.cls` `FromRow` 65-120 (setting branch 92-97 is the precedent; repair keys 98-114). `Live/Payload/Part/DryRun.cls` (Before/After MAXLEN 1000). `Live/Payload/Mailbox.cls` (unchanged). `web/scripts/payloads.mjs` generates `web/src/app/live/payloads.ts` (`DryRun` 18-28, `ApprovalPayload` 195-214).
- Web: `approvals/approval-view.ts` (`APPROVAL_TEXTS` 39-68, `approvalView` 295-327 with a binary kind check at 298, `settingView` 242-251, `resultView` 411-461), `approvals/approval-request-card.ts` (setting block 116-121, dry block 124-154; `.action` pre-line 273-276), `rail/rail-view.ts` `approvalTitle` 178-191, `incidents/incident-view.ts` `bandsOf` 380-390, `phone/phone-request.ts` (names through `approvalView`), `devices/device-panel.ts:86-89` (`<app-simulated-label />`), `mailbox/simulated-mailbox.ts` (open view 190-218; body pre-line, so no change is needed).
- More to try: `web/src/app/guide/more-to-try-view.ts` (header 2-3 "the registry of\n * its N items", texts 21-76, `MoreToTryAction` 90, `MORE_TO_TRY_ITEMS` 102-111), `more-to-try.ts` `press()` 209-240 (memory sends a prompt through `outbox.send`, 229-233), `src/ocutalon/cls/OcuTalon/Demo/Features.cls` `Ids` 39-48. Pins: `web/scripts/more-to-try-view.test.mjs` 31 (RULED), 85 (IDS), 199-211 (header, README, EXPERIENCE counts), `Test/Demo/Features.cls` `TestIds` 49-59, `web/e2e/guide/more-to-try.spec.ts`.
- `README.md` line 30 ("{N} more things to try"); New since 1.0.0 is lines 32-42 (23.6's bullet last today; 23.2's goes after it). `docker/tests/test-readme.sh:1173-1184` (telegram-demo rule).
- `EXPERIENCE.md` (`_bmad-output/planning-artifacts/ux-designs/ux-OcuTalon-2026-10-16/`): 245 (count), 246-253 (items), 254-256 (hand-off), 999 (FR-29 line).
- Mock: `ci/mock/mock.mjs:24-41` (marker, then B/ prompt scenario, then mock key), `ci/mock/scenarios/A/incident-dismiss.json` (tool-call shape), `A/digest-summary.json` (text shape), `B/try-it-anything-wrong.json` (prompt shape).
- e2e helpers: `web/e2e/support/approvals.ts` (`DRY_RUN` 27, `raise` 67, role `OcuTalonUser` 70), `support/iris.ts` (`fixtureUser` 71, `seedApproval` 731), `support/devices.ts` (`mailRowsOf` 216).

## Tasks & Acceptance

**Execution:**
- Task 0 (measure, on a fresh throwaway, in `Test.Fix.PartnerTurns`'s first case; record under `## Verification` and Design Notes): with the CI mock, measure the time from the tool's `drafting` answer to the raised request while the asking chat turn finishes on ChatAgent (pool 1). Expected under 20 s. If the draft's Decide timer fires while the turn is queued (fallback `timeout`), stop with `## Clarification Needed`.
- `src/ocutalon/cls/OcuTalon/Fix/PartnerContacts.cls` (new, Lane A) -- the read-only, demo-only fixture. `XData Contacts` JSON `[{"id": 1, "production": "OcuTalon.Demo.Orders.Production", "name": "Results Partner IT", "address": "it@results-partner.example"}]`. `For(production) As %DynamicArray` returns that production's contacts in id order, and only when `Demo.Guide.DemoOn()`, else `[]`. `Named(production, id)` returns one contact or "". It has no write method, row, global or setting.
- `src/ocutalon/cls/OcuTalon/Fix/Kind.cls` -- widen the contract.
  - `TARGETTYPE` "contact" means targets are partner-contact ids.
  - `Parameter DRAFTED = 0`: the kind's text is drafted by the model through `IncidentManager` before its dry run.
  - `Parameter MOVES = 1`: 0 means its requests never move the incident's state.
  - `Parameter NOTSETUP` is a kind reason.
  - `ClassMethod Ready(incident, Output reason) As %Boolean` defaults to 1.
  - `KINDS` gains `OcuTalon.Fix.Kind.PartnerWarning`.
  - Update the header: Execute's result for contact kinds is `{"deliveries": [{"id", "name", "address"}], "skipped"}`.
- `src/ocutalon/cls/OcuTalon/Fix/Kind/PartnerWarning.cls` (new) -- the kind.
  - Parameters: `NAME` `partner_warning`, `PARAMETERS` `text,to`, `RESOURCES` "", `TARGETTYPE` contact, `DIAGNOSED` 0, `ASKED` 1, `DRAFTED` 1, `MOVES` 0, `NOTICEMAX` 1000, `SYSTEMNOTE` (agent text, `## Public Text`), and the reasons of `## Public Text`.
  - `Facts(incident) As %String`: the code-built input lines (partner names; production display and name; failed item(s) from `FailureGroup.OfIncident`; count with item noun from `Watch.Notice.Noun`; first and last failure as `CommandCall.TimeLabel`; `Cause`). Nothing else.
  - `CheckParameters`: the base check, then `text` is one line, no control characters, at most `NOTICEMAX`; `to` is a comma list of addresses (the signature has no incident, so the fixture comparison is in `DryRun`).
  - `DryRun`: refuses when `PartnerContacts.For(incident's production)` is empty (`NOCONTACTS`) or `to` is not exactly its addresses in id order. Targets are the contact ids. The dry run is `{notice: text, recipients: [{name, address}], simulated: 1}`.
  - `Ready`: 0 with `NOTSETUP` when `'Demo.Guide.DemoOn()`.
  - `Recheck`: each id is still `Named` with the address at its position in `to`; otherwise it is skipped with "{name} is no longer a partner contact of {production}".
  - `Execute`: `{"deliveries": [...], "skipped": []}`. It sends nothing itself.
- `src/ocutalon/cls/OcuTalon/Fix/Msg/PartnerNotice.cls` (new, `Extends Ens.Request`) -- `SessionRef`, `ApprovalRef`, `IncidentRef`, `CatalogKey`, `Slots` (subject), and `Text` (the body, MAXLEN ""). Default storage, like `Fix.Msg.DryRun`.
- `src/ocutalon/cls/OcuTalon/Fix/Executor.cls` -- in `Run`, a kind whose `TARGETTYPE` is contact takes a contact branch:
  - It skips `NotRunning`.
  - It calls the kind's `Ready`; 0 ends in `CouldNotStart(row, total, reason, 1)`.
  - Then `Check`/`Carry`.
  - Then `Deliver(row, incident, parameters.text, deliveries, .sent, .failed)`: for each delivery and each session of `Data.Session.Recipients(incident.OwnerRef, incident.Ref)`, one `SendRequestSync("SimMailboxOut", PartnerNotice)` with `CatalogKey` `partner.subject` and slots `{recipient: "Name <address>"}`. A recipient counts as sent when at least one copy was saved. A send that errs is logged (Type 3, redacted) and the recipient is skipped with `NOSTART`.
  - Then `Finish(row, run, "done", {total, resent 0, completed sent, failedAgain 0, skipped total-sent, reason first skipped})`. With nothing sent and every recipient erring, it ends in `CouldNotStart` with the kind's `NOSTART`.
  - `ActionEntry` for contact kinds: the target is "{n} partner contacts of {production} (simulated)", with the contact ids and no addresses.
  - Update the class description.
- `src/ocutalon/cls/OcuTalon/Channel/SimMailbox/Out.cls` (Lane B, AD-33 exception) -- one `MapItem` `OcuTalon.Fix.Msg.PartnerNotice` -> `OnPartnerNotice`: `IsSession`; Subject is `Render(CatalogKey, Slots, "mailbox")`; `Text` is `request.Text` unrendered; Direction out; Sender OcuTalon; `Keep(message, CHANNEL, request.ApprovalRef, "", "", .row)`; `Announce`. It shares one private helper with `OnOutbound` for the row and save (extend, don't copy). Update the description. `Data/SimMessage.cls` -- doc of `ApprovalRef`: also a partner notice's request.
- `src/ocutalon/cls/OcuTalon/Watch/Msg/Draft.cls` (new, `Extends Ens.Request`) -- `IncidentRef`, `SessionRef`, `FixKind`.
- `src/ocutalon/cls/OcuTalon/Watch/IncidentManager.cls` --
  - In 23.2's `Asked`, a kind with `DRAFTED` 1 does the following before any dry run:
    - parameters other than `{}` give `refused` `NOITEM`;
    - a pending or approved request of the incident with the same `FixKind` gives `already_asked` (FixParameters are not compared);
    - an empty `PartnerContacts.For` gives `refused` `NOCONTACTS`;
    - `Allowance.MailAllowed(sessionRef, now, , , contacts.%Size())` 0 gives `refused` `ALLOWANCE`;
    - `MOVES` 0 skips the transition check.
    - It then starts the draft (`StartDraft`: async self-send of `Watch.Msg.Draft` in the incident's trace session, like `Start`) and answers `drafting` with `MESSAGEDRAFTING`.
  - `OnRequest` routes `Watch.Msg.Draft` to `Drafting(draft)`. It reopens the incident (stopping on closed or missing), builds `DraftRequest(incident, draft.SessionRef)`, and sends `SendRequestAsync("Decide", request, 1, DRAFTKEY)`.
    - `DraftRequest` copies Digest's shape: Kind turn, untrusted, fresh, `Input` = `Agent.Input.Render` of a carrier Item (Channel "system", Subject "Partner delay notice", Text = `PartnerWarning.Facts`), new ItemId, OwnerRef the asking session, `SystemNote` = the kind's `SYSTEMNOTE`.
  - `OnResponse` and `OnError` handle `DRAFTKEY` for a `Draft` request through `Drafted(draft, answer)`.
    - The draft fails on a non-Reply answer, a Fallback, an empty text, or a text over `NOTICEMAX` after normalising (strip; CR/LF runs to one space; control characters out).
    - It also fails (Type 4 line, nothing sent) when an `already_asked` match now exists.
    - Otherwise parameters are `{"text", "to"}`, and it goes through the dry run and raise tail that 23.2's `Asked` uses. Extract that tail into `RaiseAsked(incident, kind, parameters, sessionRef, Output outcome, Output ref)` and use it from both: a sync dry run, then `RaiseFix`, then `RequestRefs`, then `Move` with one `approval` Notification of `Notice.AskedKey(kind)`/`AskedSlots`.
    - For a `MOVES` 0 kind, `Move(incident, incident.State, incident.OpenVariant, notification)`.
    - A refused dry run or a failed raise also fails the draft.
    - A failed draft sends `result.partnerNotDrafted` (kind result, no ApprovalRef) to the recipients.
  - `Event`: when the own request's kind has `MOVES` 0, call `Aside(incident, event, own, notification)` instead of `Apply`.
    - `Aside` refuses on `closed` (`Drop`).
    - Otherwise, on approved it calls `Execute(incident, own)` at once. On every event it calls `Move` to the same state with the notification.
  - `Facts` skips requests whose kind has `MOVES` 0.
  - Update the description.
- `src/ocutalon/cls/OcuTalon/Watch/Notice.cls` --
  - `AskedKey(partner_warning)` is `incident.partnerRequest`. `AskedSlots` gives `{recipients: "Name <address>, ...", notice}`.
  - `ResultKey(state, result, kind)` for `partner_warning`:
    - failed with Reason = `NOTSETUP`: `result.partnerKept`;
    - Completed = Total > 0: `result.partnerSent`;
    - 0 < Completed < Total: `result.partnerSentSome`;
    - otherwise: `result.partnerNotSent`.
  - `ResultSlots` gives count, completed, total and reason.
- `src/ocutalon/cls/OcuTalon/Watch/Summary.cls` -- by kind: `summary.requestedPartner` (count = recipients); run end `summary.partnerSent`/`partnerKept`/`partnerNotSent` instead of `summary.fixEnded`. No message counts (23.2 sums message kinds only).
- `src/ocutalon/cls/OcuTalon/Core/Allowance.cls` and `src/ocutalon/cls/OcuTalon/Data/Ownership.cls` (Lane B, AD-33 exception):
  - `MailAllowed(sessionRef, now, .retryAt, .sc, more As %Integer = 1)` counts incoming emails plus partner notices (`Ownership.PartnerNotices(sessionRef, since, .oldest, .sc)`, new: SimMessage rows Kind mailbox, Direction out, ApprovalRef not empty). It is allowed when count + more <= `EMAILLIMIT`. `oldest` is the older of the two.
  - Existing callers are unchanged. Update both descriptions.
- `src/bridge/cls/OcuTalon/Bridge/Data/ApprovalRequest.cls` -- `DRYRUNKEYS` gains `notice,recipients,simulated`.
- `src/ocutalon/cls/OcuTalon/Channel/Telegram/In.cls` -- `PressText`: an approved `partner_warning` uses `press.approvedPartner`.
- `src/ocutalon/cls/OcuTalon/Msg/Catalog/Watch.cls` -- one appended block after 23.2's with the `incident.`, `result.`, `summary.` and `partner.` keys of `## Public Text` (source: Story 23.5). `Msg/Catalog/Core.cls` -- one appended `press.approvedPartner` entry (the `press.` prefix lives there; if 23.2 has placed `press.` keys elsewhere, follow where the prefix is when implementing and keep it in one class).
- `src/ocutalon/cls/OcuTalon/Tools/WatchTools.cls` and `Tools/Watching.cls` -- in 23.2's `ProposeFix`, `partner_warning` resolves the incident in states `open,awaiting_approval,fixing,resolved` and passes `{}`, or `{"item"}` when an item was given. The tool description gains the kind ("no item"). The answer outcome `drafting` passes through. `Agent/Chat.cls` -- one INSTRUCTIONS line (Public Text, agent text).
- `ci/mock/scenarios/A/partner-warning.json` (toolUse `propose_fix {kind: partner_warning}`, then text), `A/partner-warning-injected.json` (toolUse with `item: "orders@attacker.example"`), `A/partner-notice.json` (text: a CI-mock draft of one paragraph), `B/partner-warning-ask.json` (prompt "Warn the partner about the delay.") and `B/partner-notice-draft.json` (prompt: the SYSTEMNOTE's first sentence, mock key chat).
- `src/ocutalon/cls/OcuTalon/Install/SecurityOverview.cls` -- the kind row with resources "none" and risky. Regenerate `docs/security-overview.md`.
- `src/ocutalon/cls/OcuTalon/Live/Payload/Part/DryRun.cls` and `Live/Payload/Approval.cls` (Lane B) -- `Notice` (MAXLEN ""), `Recipients` (list of "Name <address>") and `Simulated`. The branch is `FixKind` = `partner_warning`, with no repair keys. The incident payload's request entries carry `fixKind` (add it in `Live/Payload/Incident.cls` if 23.2 did not). Run `npm --prefix web run payloads`.
- Web (Lane B):
  - `approvals/approval-view.ts` and `approval-request-card.ts`: a `partner` branch with title and action, a To line with `<app-simulated-label />`, the notice (pre-line), the note, and its `resultView` band texts.
  - `rail/rail-view.ts` `approvalTitle`.
  - `incidents/incident-view.ts` bands by `fixKind`.
  - `phone/phone-request.ts` button names, through `approvalView`.
- More to try: `guide/more-to-try-view.ts` (texts, `MoreToTryAction` `partnerWarning`, registry after 23.2's `reroute`, header count), `more-to-try.ts` (`press()` sends `partnerPrompt` through `outbox.send`, like memory), `Demo/Features.cls` (`partnerWarning` after `reroute`, always; description).
- `README.md` -- line 30 count per the registry; the bullet appended LAST in New since 1.0.0. `EXPERIENCE.md` -- the marked lines of `## Public Text`, only after the Planner's ruling.
- Tests (update every pin that the Shared surfaces line names, then add):
  - `Test/Fix/PartnerWarning.cls` (new): Facts exact; CheckParameters/DryRun refusals; Recheck skips; Ready; Execute with no approved row; tampered row.
  - `Test/Fix/PartnerDraft.cls` (new): through the IncidentManager probe: drafting, raise, already_asked, NOITEM, NOCONTACTS, ALLOWANCE, draft failure, state never moved on raise/approve/reject/expire/result, Facts exclusion.
  - `Test/Fix/PartnerTurns.cls` (new, fresh, running production): Task 0; the marker turn; byte-for-byte to the mailbox; demo off kept; injected; second session.
  - Extend: `Test/Fix/Kind.cls`, `Test/Fix/Refused.cls`, `Test/Watch/Summary.cls`, `Test/Core/Allowance.cls`, `Test/Demo/{Features,Guide,SimMailboxOut}.cls`, `Test/Msg/Catalog.cls`, `Test/Install/SecurityOverview.cls`, `Test/Live/Payloads.cls`, `Test/Channel/TelegramIn.cls`, the tool-list tests, and `web/scripts/{approval-view,approval-sources,rail-view,incident-view,phone-request-sources,more-to-try-view,more-to-try-sources,ux-strings}.test.mjs`.
  - e2e: `web/e2e/cards/approval-card.spec.ts` (AC14), `web/e2e/guide/more-to-try.spec.ts` (AC15).

**Acceptance Criteria:**
- AC1: Given demo mode on and the session's noticed incident (not closed), when the user asks in the chat for a partner warning, then the tool answers `drafting`, and the notice is drafted through `Decide` (one untrusted, fresh turn) whose input is exactly `PartnerWarning.Facts`: no sample error, body, setting value or evidence. Then exactly one `partner_warning` request is raised, holding the exact text and recipients (`Test.Fix.PartnerWarning`, `Test.Fix.PartnerDraft`).
- AC2: Given a raised partner request, when the sessions are told, then its stored dry run and the approval notification show the exact text and every recipient, labelled simulated. The web card, the Simulated phone and Telegram render it (`Test.Fix.PartnerDraft`, `Test.Msg.Catalog`, web unit tests).
- AC3: Given recipients, when the request is raised and again before sending, then each is a fixture contact of that production. Any other address is refused and never used, and a recipient removed since the dry run is skipped and reported (`Test.Fix.PartnerWarning`).
- AC4: Given an approved request, when FixExecutor runs it from the row, then each re-checked recipient's notice reaches the session's Simulated mailbox with `SimMessage.Text` equal byte for byte to the row's text. The result reports how many were sent, and one Action audit entry is written (`Test.Fix.PartnerTurns`).
- AC5: Given a partner request, when it is rejected or expires, then nothing is sent and the answered notice reaches each recipient (`Test.Fix.PartnerDraft`).
- AC6: Given an approved partner request and demo mode switched off, when FixExecutor runs it, then nothing is sent, the row keeps the text, and `result.partnerKept` says email delivery isn't set up yet (`Test.Fix.PartnerTurns`).
- AC7: Given no partner contact for the production (demo mode off, or another production), when a warning is asked for, then no notice is drafted or raised (`Test.Fix.PartnerDraft`).
- AC8: Given no approved row, an injected email asking to add an address, or an approved row tampered with an unconfigured address, when `Execute` or the injected turn runs, then nothing is sent, no unconfigured address is ever used and the fixture is unchanged (`Test.Fix.PartnerWarning`, `Test.Fix.PartnerTurns`, `Test.Fix.Refused`).
- AC9: Given the guide's resolved incident, when a partner request is raised, approved and carried out, rejected or expired, then the incident's state and open variant are unchanged, the guide stays finished, and a later fix request's transitions ignore it (`Test.Fix.PartnerDraft`, `Test.Demo.Guide`).
- AC10: Given the online demo, when a session has used its 20 simulated emails in the hour (incoming and partner notices together), then a partner warning is refused before drafting, and sent notices count toward the incoming-email limit (`Test.Core.Allowance`, `Test.Fix.PartnerDraft`).
- AC11 (Integration): Given the running production and the CI mock marker turn, when the turn and the draft end, then `WebChatOut` records the asking session's `approval` Delivery for the new request. After approval, `SimMailboxOut` publishes one `mailbox` event to that session only, and a second session gets neither (`Test.Fix.PartnerTurns`).
- AC12: Given a partner warning being drafted, when Decide answers with a fallback, an error or an unusable text, then nothing is raised and `result.partnerNotDrafted` reaches the recipients (`Test.Fix.PartnerDraft`).
- AC13: Given an incident with a partner request, when it closes, then its summary has the requested and ended lines and the message counts are unchanged (`Test.Watch.Summary`).
- AC14: Given a seeded partner request, when the unprivileged LIVE fixture user (`OcuTalonUser` only) reads `GET /api/v1/state` and answers over real HTTP, then both are 200 and the payload carries `fixKind`, `notice`, `recipients` and `simulated`. A second session sees neither the request nor the mailbox message (`web/e2e/cards/approval-card.spec.ts`, CI).
- AC15: Given the guide finished, when the visitor presses More to try's "Ask for a partner warning", then the prompt is sent once as their message and a partner request card appears; after approval the Simulated mailbox lists the notice. The README's last New-since bullet and the counts follow the registry (`more-to-try.spec.ts`, CI; `more-to-try-view.test.mjs`).
- AC16: Given every new catalog and web text, when tested, then none says or implies that a real email was sent: each partner result names the Simulated mailbox or the draft (`Test.Msg.Catalog`, `ux-strings.test.mjs`).

**Added from the Planner's 23.5 rulings (2026-11-09):**
- AC-NOOPEN: Given a session with no incident of its own that isn't closed, when it asks for a partner warning, then `propose_fix` answers plainly that there is no open incident to warn about ("There's no open incident to warn the partner about, so no delay notice was drafted" if a reason string is needed), and nothing is drafted or raised.
- AC-NOTDRAFTED-WEB: Given a draft that fails, when `result.partnerNotDrafted` is sent, then the web chat shows it as a notice card (as well as the Simulated phone and Telegram), with a test.
- AC-S6P: Given the release evaluation, when the cases where the user didn't ask run (injection included), then no `partner_warning` request is raised.

## Spec Change Log

- 2026-11-10 (runner): lead note before implement: 23.2 delivered (build on its code), More to try groups and count twelve, 37.2 interplay, spine lines written.

- 2026-11-10 (runner): More to try groups ruling recorded [AMENDED 2026-11-10, Contest Planner ruling].

- 2026-11-09 (runner): Contest Planner rulings on 23.5 recorded [AMENDED 2026-11-09, Contest Planner ruling]: three text edits, the no-open-incident answer, the web-chat condition replacing the residual, S6 for partner_warning; press.* keys in Catalog.Core.

## Review Triage Log

## Design Notes

**Architecture decisions:** AD-1 (tool -> command -> owner), AD-4 (ownership; mailbox copy per owning session), AD-6 (the draft is a Decide `turn`, a new caller like Digest), AD-10 (the gate denies `propose_fix` untrusted), AD-11 (row is the truth), AD-14 (SimMailboxOut), AD-15 (IncidentManager raises; partner requests do not move state), AD-16 (kind, row-only execution, re-check), AD-17 (one audit writer), AD-20 (allowance), AD-24 (no grant), AD-29/AD-33 (lanes; exception below), AD-32 (catalog; the body is not a template).

**[RULED 2026-11-09, owner re-plan, Contest Planner ruling (iii)] Partner contacts.** Contacts come from a read-only, demo-only fixture, seeded with the Orders production's partner as the demo guide names them. It is clearly simulated: an example.com-style address under the demo's own fictional partner name, Results Partner IT <it@results-partner.example>, with no real company or person. It is shown labelled "Simulated" in the approval and in the Simulated mailbox, and loaded only in demo mode. On an own install with no contact table, no notice is drafted. With demo mode off, an approved notice is kept as an approved draft with a plain line that email delivery isn't set up yet (never silently dropped; a test pins it). No public text says or implies a real email was sent. The real `PartnerContact` table stays with Stories 36.2 and 24.2 (parked): it is not built here and nothing depends on Epic 36 or Epic 24. Delivery goes through `Channel/SimMailbox/Out`, never `EmailOut`. The approval covers the exact text and the recipients shown.

**Why a separate Decide turn (decided in-stage).**
- The plain cause is model-written from untrusted evidence, so the trusted tools keep it out of their output (`RecentActivity.cls` doc 15-17). If the chat model drafted the text, it would need the cause in a trusted output (breaking the taint rule) or in a tainted turn (where the gate denies `propose_fix`).
- An untrusted, fresh turn with a code-built input is Digest's summary pattern (`Digest/Process.cls:556`). It can call no acting tool, and a person approves its exact output.
- The turn runs on ChatAgent (pool 1) after the asking turn, so the tool cannot wait for it: the ask answers `drafting` and the request arrives as an approval notification (Task 0 measures the delay).

**Why partner requests don't move the incident (AD-15 note, veto item).** Under the current table, rejecting a partner notice on the guide's resolved incident would reopen it as "open (rejected)", which claims that a fix was rejected. It would also drop the guide out of its finish state. A notice is not a fix of the failure, so `MOVES` 0 keeps the state and still tells the sessions on every event.

**Decided in-stage.**
1. Chat-asked only. The AC's "when the incident's notice is built" trigger is not built: drafting at every notice would add a model request and an approval card to UJ-1's incident (demo path first). This follows 23.2's ruled reading of a diagnosis-proposed fix. It is listed under Veto-window items.
2. Recipients: the one fixture contact the Planner named. The demo's `order-partner.example` is the suspicious sample's sender (`SimMailbox/In.cls:50`), so it is never a contact.
3. The draft is normalised to one paragraph at most 1000 characters before the dry run, because `Catalog.Render` drops slot line breaks; the phone and Telegram therefore show the same text the card does.
4. The allowance is checked at ask time only. At most one partner request per incident is pending or approved, so the overshoot is bounded by the fixture's contact count.
5. A mailbox copy goes to each recipient session of the incident. A recipient counts as sent when one copy is saved.
6. A failed draft is told through a `result` notification without an ApprovalRef. The web chat keeps it as a Delivery row only (`WebChatOut` 31-35), so on the web the chat's own `drafting` answer is the only line. This is an accepted residual.
7. Concurrent asks: the second ask before the raise starts a second draft that raises nothing (no new column for an in-flight marker).

**AC evidence already delivered:**
- `Execute` is refused without an approved row (`Fix/Executor.cls:199-207, 246-252`).
- Approved, rejected and expired notices exist (`IncidentManager.AnswerNotice` 1273).
- The gate denies a safe, non-read-only tool in an untrusted or tainted turn (`Gate.cls:169`).
- The security overview lists `Fix.Kind.Classes()`.
- `SimMailboxOut` already saves and publishes sent mail for a session owner only.

This story adds per-kind tests for each.

**Extend, don't copy.**
- `PartnerWarning` follows the `Fix.Kind` contract.
- `RaiseAsked` is extracted from 23.2's `Asked` and serves both.
- `StartDraft` mirrors `Start`.
- `OnPartnerNotice` shares `OnOutbound`'s row and save helper.
- `MailAllowed` gains `more`.
- `Facts` reuses `RecentActivity.Entry`'s helpers.
- The web partner branch follows the setting branch.
- `Fix.Msg.PartnerNotice` mirrors `Fix.Msg.DryRun`.
- **Copy:** `DraftRequest` copies the 12-line shape of `Digest.Process.SummaryRequest`. That method is a private instance method of another area's process, and the two differ in channel, subject and note. A shared builder would change Digest for 12 lines.

**Integration ACs:** AC11 (WebChatOut and SimMailboxOut deliver from a chat turn) and AC14.
- **Consumes:** 23.2's `propose_fix`, `ProposeFix`, `Asked`, `RaiseFix`, `TARGETTYPE`/`ASKED`/`DIAGNOSED` and `Notice.ResultKey(kind)`; `Fix.Executor`; `Bridge.Approval.Raise`; `Bridge.Process.Decide`; `Channel.SimMailbox.Out`; `Core.Allowance`; `Watch.Summary` (23.6); `Demo.Guide.DemoOn`; `Data.Session.Recipients`.
- **Consumed-by:** the parked 23.5 follow-up under Epic 21 (real delivery through `EmailOut` replaces the `Ready`/`Deliver` contact branch) and Stories 36.2/24.2 (the real contact table replaces `Fix.PartnerContacts`).

**Ledger:** inbox empty.

**Contended:**
- `Agent/Chat.cls` (Epic 41): one INSTRUCTIONS line in its own hunk (ruling: plain union).
- `Msg/Catalog/Watch.cls` and `Test/Msg/Catalog.cls` (Epic 35): one appended block; the key-count pin is the union (ruling).
- `Msg/Catalog/Core.cls` (Epic 35): one appended entry, `press.approvedPartner`.
- `EXPERIENCE.md`: marked additive lines after the ruling.
- Untouched: `Core/CommandsIn.cls` (23.2's verb is reused), `Web/Api.cls`, `ci/units.sh`, `src/short-names.tsv` (no new area, no new class with a global; the message classes use the Ens.Request extents).

**Contest Planner rulings on 23.5 [AMENDED 2026-11-09, Contest Planner ruling] (2026-11-09 ~22:35Z, owner delegation; relayed by the orchestrator; binding for implement, QA and review):**
- Public Text approved as drafted except: (1) the `summary.partner*` lines are lower case after the colon (applied under `## Public Text`); (2) the More to try lookFor is the ruled text (applied); (3) with no incident of the session's own that isn't closed, `propose_fix` `partner_warning` answers plainly that there is no open incident to warn about (as 23.2's S4), with a test; if a new reason string is needed it is exactly: "There's no open incident to warn the partner about, so no delay notice was drafted". The label "Warn the partner", the button and the prompt are approved as drafted.
- CONDITION, replacing the accepted residual: `result.partnerNotDrafted` must reach the web chat too, as a notice card like the other notifications, with a test. The implement stage estimates it first: if it costs more than about an hour of work, HALT with an intent gap naming the estimate (the lead reports to the Planner) before accepting the residual.
- Approved as drafted: the other catalog keys, the refusal reasons, the command result, the draft instruction, the `Agent/Chat.cls` line and the web texts; `press.approvedPartner` (and 23.2's `press.*` keys) in `Msg/Catalog/Core.cls`, appended as a plain union with Epic 35's keys; the fixture "Results Partner IT" <it@results-partner.example>, demo mode only; the README bullet appended last with the count following the registry rule; the EXPERIENCE lines with edit 2; the veto items (the `partner_warning` kind; no privilege, role or grant; the DryRun keys; `PartnerNotice` and `Draft`; `Fix.PartnerContacts`; the allowance count; the payload fields with LIVE fixture user plus second-session tests); the behaviour readings (chat-only; the contacts note supersedes "no warning on the online demo"); the spine notes AD-14, AD-15 (a warning request never moves incident state), AD-16, AD-20, AD-32 (the runner writes them with the marker [ADDED 2026-11-09, Story 23.5, Contest Planner ruling] before implement); the AD-33 cross-lane list, additive only, plain union.
- S6 extends to this kind: the release evaluation shows no `partner_warning` request raised where the user didn't ask, injection cases included.

**More to try groups [AMENDED 2026-11-10, Contest Planner ruling] (Planner ruling 2026-11-10 ~01:30Z with its ~01:40Z correction, `prompts/more-to-try-groups-ruling.md`):** three headed groups, rendered by Epic 0 Story 0.22 (lane C, a separate story). In-flight stories only declare their group as an additive registry field, a plain union: incidentSummary (23.6), rejectFix, reroute (23.2) and warnPartner (23.5) declare `group: 'Incidents and fixes'`; 23.6's item stays FIRST overall. This story's item (warnPartner) declares `group: 'Incidents and fixes'` at implement. README line 30 and EXPERIENCE keep the TOTAL count per the registry rule; no other item text changes. Merge gate: 23.2 (the 10th item) merges as soon as it is green, its group field ignored until 0.22 lands; 23.5 (the 11th) does not merge to feature before 0.22 lands.

**Lead note before implement (2026-11-10, after Story 23.2 merged as feature 9f7db82c):**
- Story 23.2 is DELIVERED on this branch: build on its actual code, not on its planned spec. Check every 23.2 seam this spec names (`propose_fix`, `Msg.Command.ProposeFix`, `IncidentManager.Asked` and the raise path, `Fix.Kind` `ASKED`/`TARGETTYPE`/`DRYRUNKEYS`, the result-band rendering in `web/src/app/approvals/approval-view.ts` and `web/src/app/incidents/incident-card.ts`, the incident payload's `Production` and each request's `FixKind`/`Item`/`Count`) against the code, and extend those; where the delivered names differ from this spec's, follow the code and record it under Design Notes ("Decided in-stage").
- More to try (Story 0.22 merged): the registry holds eleven items under three headings; `warnPartner` is ONE row with `group: 'Incidents and fixes'`, after `reroute` in registry order (plus one `GROUP_OF` line in `web/scripts/more-to-try-view.test.mjs`). EXPERIENCE.md lists the items by group and numbers them in panel order: warnPartner becomes Item 3 under "Incidents and fixes" and the items after it are numbered one higher (with the hand-off lines and the first-item line updated); the count becomes TWELVE in README line 40, the `more-to-try-view.ts` header comment and EXPERIENCE.md. No new e2e K numbers collide (K25-K28 are taken).
- Story 37.2 (Usage, a fourth heading "Usage and history") may land first; whichever merges second re-integrates (plain union, counts from the registry).
- The spine lines for this story (AD-14, AD-15, AD-16, AD-20, AD-32, [ADDED 2026-11-10, Story 23.5, Contest Planner ruling]) are already written; AD-12's incident-payload line from 23.2 is on feature.
- The `result.partnerNotDrafted` web-chat notice card condition: estimate it FIRST; more than about an hour of work is an intent-gap HALT naming the estimate (the lead reports to the Planner).

## Public Text

All entries are drafts; the UX and PRD give no wording beyond EXPERIENCE.md:999 ("A partner warning's request shows the exact text and recipients"). Slots are in brackets.

Catalog, `Msg/Catalog/Watch.cls`, appended after 23.2's block:
- `incident.partnerRequest`: "I drafted a delay notice about this incident for {recipients}. Approve sending it?\n\nDry run: the notice below would go to the Simulated mailbox, not to a real inbox. The recipients are simulated partner contacts.\n\n{notice}\n\nNothing has been sent yet.\n\nDetails and trace: on your OcuTalon page." The web form is the same without " Approve sending it?". [recipients text, notice text]
- `result.partnerSent`: "The delay notice went to the Simulated mailbox for all {count} partner contacts. No real email was sent." The one form is "The delay notice went to the Simulated mailbox for the partner contact. No real email was sent." [count]
- `result.partnerSentSome`: "The delay notice went to the Simulated mailbox for {completed} of {total} partner contacts. Not sent to the rest: {reason}. No real email was sent." [completed, total, reason sentence]
- `result.partnerNotSent`: "The delay notice was not sent: {reason}. It needs a new approval." [reason sentence]
- `result.partnerKept`: "The delay notice is approved and kept as a draft: email delivery isn't set up yet, so nothing was sent." []
- `result.partnerNotDrafted`: "I couldn't draft the delay notice just now, so nothing was raised or sent. You can ask me again." []
- `summary.requestedPartner`: "{time}: OcuTalon asked for approval to send a delay notice to {count} partner contacts." The one form is "{time}: OcuTalon asked for approval to send a delay notice to the partner contact." [time, count]
- `summary.partnerSent`: "{time}: the delay notice went to the Simulated mailbox." `summary.partnerKept`: "{time}: the delay notice was approved and kept as a draft." `summary.partnerNotSent`: "{time}: the delay notice was not sent." [time]
- `partner.subject` (the mailbox subject, rendered by SimMailboxOut): "Simulated delay notice to {recipient}" [recipient text]

`Msg/Catalog/Core.cls`:
- `press.approvedPartner`: "Approved. Sending the delay notice to the Simulated mailbox."

Kind reasons (code, `Fix/Kind/PartnerWarning.cls`; shown through `result.partner*` and given to the chat model):
- `NOTSETUP`: "email delivery isn't set up yet"
- `NOCONTACTS`: "No partner contacts are set up for {production}, so no delay notice was drafted"
- `NOITEM`: "A delay notice takes no item or address: its recipients are the partner contacts set up for {production}"
- `ALLOWANCE`: "The online demo allows 20 simulated emails an hour, and this session has used them for now, so no delay notice was drafted"
- recheck: "{name} is no longer a partner contact of {production}"
- `NOSTART`: "OcuTalon couldn't deliver the delay notice"

CommandResult (`Watch/IncidentManager.cls`, given to the model):
- `drafting`: "I'm drafting the delay notice now. It will come as an approval request with the exact text and the recipients, and nothing is sent until it is approved."

Agent text (not shown to users):
- `PartnerWarning` `SYSTEMNOTE`: "Write a short delay notice to the partner named below about the failures described below. Use only these facts. Write one plain paragraph of two to four sentences, at most 500 characters, with no greeting line, no signature, no placeholders, no message contents and no setting values, and don't promise when it will be fixed."
- `Agent/Chat.cls` (~line 63): "If the user asks to warn or notify the partners about an incident's delay, call propose_fix with kind partner_warning and no item. Say that the notice is being drafted, that it comes as an approval request with the exact text and recipients, and that nothing is sent until it is approved; with outcome refused, give the reason."

Fixture (public, demo only): the partner name "Results Partner IT" and the address "it@results-partner.example".

Web (Lane B):
- Title (`rail-view.ts` ~43, `approval-view.ts`): "Send a delay notice". Action: "Send a delay notice."; button "Approve: send a delay notice" (existing lower-case rule).
- Card block (`approval-view.ts` ~39-68): "To: {recipients}" followed by the existing "Simulated" label; the notice as given; the note "Nothing is sent unless you approve. It goes to the Simulated mailbox, not to a real inbox."
- Result bands: "Sent to the Simulated mailbox." / "Sent to the Simulated mailbox for {completed} of {total} contacts." / "Approved and kept as a draft: email delivery isn't set up yet." / "Not sent: {reason}."

More to try (`more-to-try-view.ts`, after 23.2's `reroute`):
- label: "Warn the partner"
- lookFor: "This asks OcuTalon in the chat to warn the partner about an incident's delay, so it needs an incident that isn't closed: if you closed the guide's incident, do "Reject a fix" first. OcuTalon drafts a short notice from the incident's counts, times and cause, and it comes as an approval request that shows the exact text and the recipients, simulated contacts. Approve it, then open the Simulated mailbox to read the notice exactly as you approved it. Nothing goes to a real inbox." [AMENDED 2026-11-09, Contest Planner ruling]
- button: "Ask for a partner warning"
- partnerPrompt (sent as the visitor's message): "Warn the partner about the delay."

README (`README.md`):
- Line 30: "{N} more things to try", with N the registry's count (ten after 23.6 and 23.2).
- Bullet appended LAST in New since 1.0.0: "- **Partner delay notices.** Ask OcuTalon in the chat to warn the partner about an incident's delay. It drafts a short notice from the incident's count, times, affected flow and cause, never from a message's contents, and raises it as an approval request that shows the exact text and every recipient. Nothing is sent until you approve. In demo mode the partner contacts are simulated and the approved notice goes to the Simulated mailbox, not to a real inbox; without demo mode there are no partner contacts yet, so no notice is drafted. Try it: after the guide's incident, More to try, *Warn the partner*."

EXPERIENCE.md (marked, after the ruling):
- 245: the count per the registry.
- A new Item bullet with the More to try texts above.
- A hand-off bullet: "Item {n} sends "Warn the partner about the delay." as the user's own message".
- 999 appended: "On the demo the recipients are simulated contacts, and the approved notice goes to the Simulated mailbox."

## Veto-window items

- **New fix kind:** `partner_warning`: an outward (simulated) send. It sits behind one approval whose dry run holds the exact text and every recipient. It is asked for in the chat only and denied in untrusted or tainted turns. Recipients come only from the fixture and are re-checked before sending, and the sent text is the approved row's byte for byte.
- **Privileges, roles, grants:** none. `RESOURCES` is empty (the send stays inside OcuTalon's own production). No grant to any role.
- **Security posture:** OcuTalon can now put a model-drafted, person-approved text into the Simulated mailbox. Every run is audited (Action entry with counts and contact ids, no addresses).
- **Stored data:**
  - No new table or column.
  - `ApprovalRequest.DryRun` gains `notice`, `recipients` and `simulated`; `FixParameters` holds `{text, to}`.
  - SimMessage rows of sent partner notices carry their ApprovalRef (existing column).
  - New message classes: `Fix.Msg.PartnerNotice` and `Watch.Msg.Draft` (Ens message storage, purged with messages).
  - A code fixture, `Fix.PartnerContacts` (read-only, demo only).
  - Retention unchanged.
- **Outward sends:** to the Simulated mailbox only. No `EmailOut`.
- **Allowance:** partner notices count toward the online demo's 20 simulated emails an hour (incoming and notices together).
- **Routes:** none new. The `GET /api/v1/state` and `POST /api/v1/approvals/:ref/answer` payloads gain `notice`, `recipients` and `simulated` (AC14: LIVE fixture user plus a second-session check).
- **Behaviour reading:** the "when the incident's notice is built" trigger is not built (Decided 1). The AC's "no warning on the online demo" is superseded by the Planner's note.
- **Architecture decisions (for the lead, Rule 20):**
  - AD-14: `SimMailboxOut` also takes `Fix.Msg.PartnerNotice` from `FixExecutor` (a simulated outward notice, body verbatim, subject from the catalog).
  - AD-15: a partner-warning request (kind `MOVES` 0) never moves the incident's state and is not counted in the table's facts. `IncidentManager` drafts it through an async self-sent `Watch.Msg.Draft` and a Decide `turn` before raising it.
  - AD-16: the kind `partner_warning`, with `TARGETTYPE` contact. `DRYRUNKEYS` gains `notice`, `recipients` and `simulated`; the `Ready` hook covers a kind whose delivery isn't set up; the executor delivers contact plans to `SimMailboxOut`.
  - AD-20: `MailAllowed` counts partner notices.
  - AD-32: new keys, the `partner.` prefix in `Catalog.Watch`, and `press.approvedPartner` in `Catalog.Core`. The notice body is approved model text, never a catalog template.
- **AD-33 cross-lane exception request (Lane B files, additive branches only):**
  - Classes: `Channel/SimMailbox/Out.cls`, `Data/SimMessage.cls` (doc), `Core/Allowance.cls`, `Data/Ownership.cls` (new query), `Live/Payload/Approval.cls`, `Live/Payload/Part/DryRun.cls`, `Live/Payload/Incident.cls` (if needed), `Demo/Features.cls`.
  - Web: `web/src/app/{live/payloads.ts, approvals/*, rail/rail-view.ts, incidents/incident-view.ts, phone/phone-request.ts, guide/*}`.
  - Their tests: `Test/Core/Allowance.cls`, `Test/Demo/{Features,Guide,SimMailboxOut}.cls`, `Test/Live/Payloads.cls`, `web/scripts/*`, `web/e2e/cards/approval-card.spec.ts` and `web/e2e/guide/more-to-try.spec.ts`.
- **Public text:** every string of `## Public Text`.
- **Dependencies:** none.

## Verification

Run every command from the epic-23 worktree root, one per call with `timeout: 600000`, each finishing in about 150 s; never two test runs in one message.
- Prefix every `ci/` call with `OCUTALON_LOCK_DIR=<main checkout>/.worktrees/.coordination/locks/lane-d OCUTALON_TEST_WEB_PORT=52804 OCUTALON_LOCK_OWNER='epic=23 stage=implement'`.
- The fresh tag is `e23s5i` and the warm tag `e23s5iw`. At the end run `ci/warm.sh down`, then `ci/iris.sh teardown` with `e23s5i`.
- Every IRIS MCP call names `server` `ocutalon-slot-d` and `namespace` `OCUTALON`. Production-running cases run on throwaways only.

**Shared surfaces:**
- `Fix.Kind` `KINDS` and every pin of the kind list: `Test.Fix.Kind`, `Test.Install.SecurityOverview` and `docs/security-overview.md`, and the Fix step's grants.
- `ApprovalRequest` `DRYRUNKEYS` and the approval payload's dry-run part (`Test.Live.Payloads`, `payloads.ts`).
- The catalog key count and fixtures (`Test.Msg.Catalog`, a union with 23.2, 23.6 and Epic 35).
- The tool description and lists (`Test.Agent.Constants`, `Test.Watch.Tools`, `Test.Agent.Instructions`).
- `Core.Allowance.MailAllowed`'s count (`Test.Core.Allowance`, `Test.Demo.SimMailboxIn` TestEmailLimit).
- `SimMailboxOut`'s message map (`Test.Demo.SimMailboxOut`).
- `Watch.Summary` lines (`Test.Watch.Summary`).
- The More to try registry: ten items in `more-to-try-view.test.mjs` IDS and RULED, the `more-to-try-sources.test.mjs` `outbox.send` pin, `more-to-try.spec.ts` and `Test.Demo.Features`; plus README line 30 and the EXPERIENCE.md count.
- The approval, rail, incident and phone web view tests.
- The mock scenario registry (`docker/tests/test-mock.sh`).

Every test added or changed passes on a fresh environment, in either order.

**Commands:**
- (once) Task 0 on a fresh throwaway: `OCUTALON_RUN_TAG=e23s5i ci/iris.sh class OcuTalon.Test.Fix.PartnerTurns`, with the measuring case first. Expected: passed, and the measured delay is printed.
- (loop) Run `ci/warm.sh up` with `OCUTALON_RUN_TAG=e23s5iw` once, then `OCUTALON_WARM=1 OCUTALON_RUN_TAG=e23s5iw ci/iris.sh class <Class>`, one call each, for: `OcuTalon.Test.Fix.PartnerWarning`, `OcuTalon.Test.Fix.PartnerDraft`, `OcuTalon.Test.Fix.Kind`, `OcuTalon.Test.Fix.Refused`, `OcuTalon.Test.Watch.Summary`, `OcuTalon.Test.Core.Allowance`, `OcuTalon.Test.Demo.Features`, `OcuTalon.Test.Demo.Guide`, `OcuTalon.Test.Demo.SimMailboxOut`, `OcuTalon.Test.Msg.Catalog`, `OcuTalon.Test.Install.SecurityOverview`, `OcuTalon.Test.Live.Payloads`, `OcuTalon.Test.Channel.TelegramIn`, `OcuTalon.Test.Agent.Constants`, `OcuTalon.Test.Watch.Tools`. Expected: each `CLASS ... passed`.
- (loop) Fresh: `OCUTALON_RUN_TAG=e23s5i ci/iris.sh class OcuTalon.Test.Fix.PartnerTurns`, then `OcuTalon.Test.Demo.SimMailboxIn`, one call each. Expected: passed.
- (loop) `node --test web/scripts/more-to-try-view.test.mjs web/scripts/more-to-try-sources.test.mjs web/scripts/ux-strings.test.mjs`, then, in one call, `node --test web/scripts/approval-view.test.mjs web/scripts/approval-sources.test.mjs web/scripts/rail-view.test.mjs web/scripts/incident-view.test.mjs web/scripts/phone-request-sources.test.mjs`. Expected: pass.
- (loop) `bash docker/tests/test-mock.sh`. Expected: pass.
- (once) `npm --prefix web run lint` and `bash docker/tests/test-readme.sh`. Expected: pass.
- **Left to CI** (each over 150 s): the browser units (`live:sign-in` parts with `approval-card.spec.ts` and `more-to-try.spec.ts`, `live:demo-path`, the online demo path), the shards, `bash ci/checks.sh`, `npm --prefix web run build`, and the lead's fresh-environment check (forward and `--reverse`).

**Mutations (Rule 19), one per AC, recorded as `mutation: <change> -> <test red>`:**
- AC1: add `incident.SampleError` to `Facts` -> `Test.Fix.PartnerWarning`.
- AC2: drop `recipients` from `AskedSlots` -> `Test.Fix.PartnerDraft`.
- AC3: let `Recheck` pass an id whose address differs -> `Test.Fix.PartnerWarning`.
- AC4: trim the text in `OnPartnerNotice` -> `Test.Fix.PartnerTurns`.
- AC5: call `Execute` on rejected in `Aside` -> `Test.Fix.PartnerDraft`.
- AC6: `Ready` always 1 -> `Test.Fix.PartnerTurns`.
- AC7: skip the `NOCONTACTS` check -> `Test.Fix.PartnerDraft`.
- AC8: set `READONLYPROPOSEFIX` 1 -> `Test.Fix.PartnerTurns` (injected case).
- AC9: route partner events through `Apply` -> `Test.Fix.PartnerDraft`.
- AC10: count incoming emails only -> `Test.Core.Allowance`.
- AC11: omit `Announce` in `OnPartnerNotice` -> `Test.Fix.PartnerTurns`.
- AC12: skip the failure notice -> `Test.Fix.PartnerDraft`.
- AC13: use `summary.fixEnded` for partner runs -> `Test.Watch.Summary`.
- AC14: drop `Notice` from `FromRow` -> `approval-card.spec.ts` (CI).
- AC15: the item sends nothing -> `more-to-try.spec.ts` (CI).
- AC16: make `result.partnerSent` read "sent by email" -> `Test.Msg.Catalog`.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
