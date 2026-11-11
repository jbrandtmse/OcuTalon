---
title: 'Story 23.5: Draft partner delay notices that are sent only after approval'
type: 'feature'
created: '2026-11-09'
status: 'done'
baseline_revision: '6943545e321320a7f33e35ffaa1933eeef75b895'
baseline_commit: '4e7cb8e7c695f5f8b6c71452ff057f57f95599a2'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-23-context.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-23-2-suspend-resume-and-reroute-with-a-dry-run.md'
warnings: [oversized]
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
    - `Aside` refuses on `closed` (`Drop`). [AMENDED 2026-11-11, Contest Planner merge-time ruling 2 on DW-1108, option (a): an approved event of a request on a closed incident is not dropped silently: the request's recipients are told `result.partnerNotSent` with an existing refusal reason, through `Aside`, and nothing is sent. Options (b) and (c) are declined.]
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

### Review Findings

Code review 2026-11-11 (epic-cycle code-review stage; layers blind-hunter, edge-case-hunter, verification-gap, acceptance-auditor; review_mode full; baseline `10f53487`, plus QA's uncommitted changes). 1 high, 5 medium and 6 low were acted on; 19 were rejected or closed (appendix).

- [x] [Review][Patch] (high) A target the fixture does not name was reported as "Partner contact {id} is no longer a partner contact of ...", a user-facing string not in `## Public Text` (it reaches `result.partnerNotSent`/`partnerSentSome`, the phone, Telegram and the web band). Fixed: such a target is skipped with the ruled NOSTART reason; RECHECK keeps naming a real contact [src/ocutalon/cls/OcuTalon/Fix/Kind/PartnerWarning.cls:Plan]
- [x] [Review][Patch] (medium) `Executor.Run` sent `FixParameters.text` with no check against `DryRun.notice`, the text the approver was shown (AD-16, the "approval covers the exact text" ruling, matrix row "Tampered row"). Fixed: `AsApproved` requires them equal, character for character; otherwise the run could not start with NOSTART and nothing is sent [src/ocutalon/cls/OcuTalon/Fix/Executor.cls:Run, AsApproved]
- [x] [Review][Patch] (medium) The incident summary wrote `summary.fixStarted` ("the fix started.") before every delay notice's end line, contradicting "a delay notice is not a fix" (AC13, Decided 12). Fixed: a contact run has its end line only (an interrupted one reads as not sent), and `TestPartnerLines` pins the absence [src/ocutalon/cls/OcuTalon/Watch/Summary.cls:RunEvents]
- [x] [Review][Patch] (medium) `Test.Fix.PartnerTurns:TestDemoModeOffKeepsTheNotice` left the production's jobs reading demo mode off for up to `CACHESECONDS` after `PutBack`, so its neighbours were green by name order only (Rule 19 hermeticity). Fixed: `OnAfterOneTest` waits out the cache after that case [src/ocutalon/cls/OcuTalon/Test/Fix/PartnerTurns.cls:OnAfterOneTest]
- [x] [Review][Patch] (medium) AC14's "a second session sees ... the mailbox message" was not checked over real HTTP. Fixed: A13 seeds one sent notice mail for this session and one for the second, and `GET /api/v1/state` lists the first (the control) and not the second [web/e2e/cards/approval-card.spec.ts:A13]
- [x] [Review][Defer] (medium) Approve-then-close loses the notice's outcome: an Execute that reaches FixExecutor after the Dismiss is refused as unusable, and a result that comes back after it is dropped by `Aside`. Same root cause as DW-1108 (occurrence added); DW-1108 re-dispositioned `decision-pending` (owner burndown, for the decision sheet) with the recommendation that `Aside` still tells the result on a closed incident, with the existing texts and no state move [src/ocutalon/cls/OcuTalon/Watch/IncidentManager.cls:Aside] — deferred: a product call on the user-facing outcome
- [x] [Review][Patch] (low) `Drafted`'s closed-incident guard had no test. Added to `TestDraftFails` [src/ocutalon/cls/OcuTalon/Test/Fix/PartnerDraft.cls]
- [x] [Review][Patch] (low) A partner run that throws used the executor's default NOREAD ("couldn't read the failed messages in that production"). Fixed: the kind's NOREAD has NOSTART's ruled words [src/ocutalon/cls/OcuTalon/Fix/Kind/PartnerWarning.cls]
- [x] [Review][Patch] (low) The fixture's no-write check looked only for methods named Save, Add and Set, and PartnerTurns' "fixture unchanged" cannot fail. Fixed: `TestNoContacts` pins the fixture's whole method list (all readers) [src/ocutalon/cls/OcuTalon/Test/Fix/PartnerWarning.cls:TestNoContacts]
- [x] [Review][Patch] (low) `Test.Demo.Guide:TestPartnerRequestKeepsTheGuideFinished`'s comment promised a second-session case it does not have. Comment corrected [src/ocutalon/cls/OcuTalon/Test/Demo/Guide.cls]
- [x] [Review][Patch] (low) `Test.Fix.PartnerTurns` called `TestAskedTurnRaisesWithinBounds` "the first case"; by name order it runs second. Comment corrected (Task 0's 0.25 s stays far inside its 20 s bound) [src/ocutalon/cls/OcuTalon/Test/Fix/PartnerTurns.cls]
- [x] [Review][Patch] (low) AC15's mutation line named a source-text test, not an executing pin. Closed in-pass: the mutation went red on K9c in `live:sign-in-3 --part 1/2` (`## Verification`)

Rejected or closed (appendix):
- `Agent/Chat.cls`'s line covers only `refused` (blind): by-design, the Planner-approved text verbatim; the other outcomes come with their own CommandResult message.
- Decided 13 overstates `aboutFix` (blind, edge): false as a code defect. A resolved card shows the diagnosis's fix sentence with or without a partner request (pre-existing); `aboutFix` only keeps a partner request from hiding a chat-kind request's sentence. The fix would be a spec edit.
- The draft's cost is not in the summary's "Model cost of this incident" (blind): low, `wontfix-accepted` (DW-1112). The draft is a turn owned by the asking session and counted on its Usage, like the chat turn that asked for it; no column links it to the incident.
- NOTSETUP is matched by its text in three places (blind): low. FixResult's fields are fixed, so a flag means a new field; the server and web tests both pin the ruled text.
- `chat-view.ts` `bareResult` shows any result with a ref and no approvalRef (blind): false. Only `WebChatOut.ToolCallCard`'s partnerNotDrafted clause publishes such a row with a card ref.
- Spec record slips (TelegramIn in Auto Run Result, "ten items"/"line 30" in Shared surfaces) (blind): the fix is a spec edit.
- `Plan` reads `to` by the position in the subset it is given (edge): `wontfix-theoretical` (DW-1110). The fixture has one contact.
- An interrupted contact run would read `result.interrupted` (edge): `wontfix-theoretical` (DW-1111). Needs a restart inside a few synchronous sends; the summary side is fixed above.
- `SendNotice` has no timeout (edge): `wontfix-theoretical`. Becomes real only if SimMailboxOut's job hangs on its own save.
- The Telegram press says it is sending after demo mode was switched off (edge): low. The press text is ruled, and `result.partnerKept` follows at once.
- `propose_fix`'s item is optional now, so an item kind without one gets the base check's technical refusal (gap): low, `wontfix-accepted`. The refusal is safe (nothing raised) and goes to the model. reopen_if: a transcript shows `propose_fix` for an item kind without an item.
- PartnerTurns' "no request"/"no mail" cannot tell a gate failure from NOITEM (gap): false. The `UNTRUSTED` step assertions pin AC8's gate.
- The guide test cannot see the step-4 defect (gap): already DW-1109.
- Lane B files outside the AD-33 list (acceptance): false as a HIGH. Each one is named elsewhere in this spec. README and the `B/` mock scenarios are in Tasks. `Channel/WebChat/Out.cls`, `chat-view.ts` and `Test.Core.WebChatOut` are the lead's recorded seam for the Planner's AC-NOTDRAFTED-WEB condition, and `web/e2e/chat/notice.spec.ts` N21 is that condition's test. `web/e2e/support/iris.ts` is in the Code Map's A13 helpers. `Live/Payload/Part/IncidentRequest.cls` is the incident payload's request part (listed "if needed", comment only). `Msg/Command/ProposeFix.cls` is the verb that 23.2 created under the spine's Lane A ruling (comment only). The Veto-window list itself is incomplete as a record; that is for the lead.
- EXPERIENCE.md's "On the online demo only the reroute is offered" (acceptance): low. It is 23.2's ruled line about its own kinds; rewording it would be unruled text.
- AC15's browser case is not end to end (acceptance): by-design (Decided 20).
- `phone-request-sources.test.mjs` was not extended (acceptance): low. The phone takes its names from `approvalView`, which `approval-view.test.mjs` pins.
- `DRAFTSUBJECT` "Partner delay notice" is not in Public Text (acceptance): false. The Tasks name it as the carrier's Subject; it is trace-only.
- Task 0 was measured after a warm-up case (gap): low; the comment is corrected above.

**Smoke rework (iteration 1):**
- [x] [Smoke] `Test.Channel.TelegramChat:TestNotices` fails on a warm stack: "there are 28 Watch notice keys" and "there are 34 of them". This story added `incident.partnerRequest` and `result.partner*` keys to `Msg/Catalog/Watch.cls`, and the test pins the count of the catalog's `incident.`/`result.` keys and the Telegram Delivery rows (Rule 19 shared surface, missed by implement, QA and review). Update the pins to what the catalog now holds, with each new key sending as the others do (the request key counts as an `approval` row, as 23.2's three request keys do); run the class on a stack and write its mutation line. No product change.
  - Done (warm tag `e23s5rw`): the pins are now 34 Watch notice keys, 40 Delivery rows, 41 notifications handled by TelegramOut (40 and the answered one) and 41 web rows (the 40 and the answered one, which WebChatOut also records; the drain guard read 40 until the code review); `incident.partnerRequest` joins the `approval` rows and the five `result.partner*` keys send as `result` rows. `Test.Channel.TelegramChat` passed (all of it, 39 s).
  - mutation: `result.partnerKept` deleted from `Msg/Catalog/Watch.cls` `Entries` (the product catalog) -> `Test.Channel.TelegramChat:TestNotices` red ("there are 34 Watch notice keys", "there are 40 of them", "TelegramOut has handled all 40 notifications and the answered one", "WebChatOut has handled all 40 notifications and the answered one"); restored byte-identical (`cmp`, `git status --short` and `git diff --stat` unchanged), the class green again on the same warm stack (`e23s5dw`, code review).

**Merge-time rework (iteration 2; Contest Planner merge-time rulings, prompts/epic-23-rulings-235.md):**
- [x] [Rework] DW-1109 (ruling 1, fix now): `Demo.Guide.Compute` counts any answered or approved request of the guide's incident for step 4, so a partner notice approved while the repair still waits marks step 4 done early. Add the one-line kind filter in `Demo/Guide.cls` (now on the AD-33 list): a request whose kind never moves the incident (`MOVES` 0, `Fix.Kind`) counts for neither `answered` nor `fixApproved`. Test (in `Test.Demo.Guide`): a partner notice approved while the repair request still waits leaves step 4 not done (and the repair's approval still marks it done). Demonstrated `mutation:` line.
  - Done (warm tag `e23s5qw`; slot D): `Demo.Guide.Compute` leaves a request whose kind has `MOVES` 0 out of `answered` and `fixApproved` (an unregistered kind or no kind still counts); `Test.Demo.Guide:TestPartnerRequestIsNotStepFour` pins it: a partner notice approved, executing, done, failed or rejected beside a waiting repair leaves step 4 not done (done "10100"), and the repair's approval marks it done ("10110"). `Test.Demo.Guide` passed (26 methods, slot D and warm).
  - mutation: the `MOVES` filter line deleted from `Demo/Guide.cls` `Compute` -> `Test.Demo.Guide:TestPartnerRequestIsNotStepFour` red (all five "partner request beside a waiting repair: done" assertions); restored byte-identical (`cmp` against the saved copy, `git diff --stat` unchanged), class green again.
  - Review patch: the test also pins the guide's `finished` (a partner request in approved, executing, done or failed state is not the approved fix of a resolved incident with the trace). mutation: the filter moved to the `answered` line only (the `fixApproved` side unfiltered) -> `TestPartnerRequestIsNotStepFour` red ("finished" for all four states); restored byte-identical (`cmp`), class green again (26 methods).
  - Code review patch (rework iteration 2): the repair request of `TestPartnerRequestIsNotStepFour` now carries a registered kind that moves the incident (`FixKind` `repair_resend`, as production repair rows do), so the "repair approved" assertion also pins that such a kind still counts. mutation: the filter widened to every registered kind (`If (kindClass '= "") Continue`) -> `Test.Demo.Guide:TestPartnerRequestIsNotStepFour` red ("the repair approved: done"); restored byte-identical (`cmp`, `git status --short` and `git diff --stat` unchanged), the method green again on slot D.
- [x] [Rework] DW-1108 (ruling 2, option (a), bounded at about 1 h; existing text verbatim, no new public text): a partner request approved after its incident was closed is no longer dropped silently. Through `IncidentManager.Aside`, the request's recipients are told `result.partnerNotSent` with an EXISTING refusal reason (prefer the kind's own `NOSTART`, "OcuTalon couldn't deliver the delay notice"; never a new sentence), and nothing is sent (no Execute, no PartnerNotice, no SimMailbox row). The same telling covers a partner result that comes back after the incident closed (approve-then-close), if it falls out of the same change. Test: ask, close, approve: one `result.partnerNotSent` told with that reason, nothing sent. Demonstrated `mutation:` line. If this cannot be done within about 1 h, or needs a new sentence, stop: leave the item unchecked, keep the frontmatter `deferred:` entry, and record "deferred to 1.0.8 per ruling 2" in `## Auto Run Result`.
  - Done (warm tag `e23s5qw`; slot D): `IncidentManager.Aside` hands a closed incident to the new `Closed`. The incident stays closed (no state or variant move, no Execute, no PartnerNotice, no SimMessage). An approved request is told to each recipient as `result.partnerNotSent` through `ResultNotice` (a `FixResult` built in memory with Final 1, Total = the targets and the kind's `NOSTART` as Reason, so `Notice.ResultKey`/`ResultSlots` give the key and the reason slot; nothing is stored). The final result that FixExecutor sends for an approved-then-closed request (refused as `UNUSABLE`) falls out of the same code: `Closed` tells the result notice it came with (`result.partnerNotSent`, the executor's existing reason). Any other event on a closed incident is still refused with the Type 4 line. No new text, no schema change; about 0.5 h.
  - Tests: `Test.Fix.PartnerDraft:TestStateNeverMoves` (closed part) now asserts one `result.partnerNotSent` for the request with `PartnerWarning.NOSTART` as the reason, no Execute, the incident still `closed`, the after-close final result told once, and a rejection and an expiry told to nobody. `Test.Fix.PartnerDraft`, `PartnerWarning`, `Demo.Guide`, `Watch.Transitions`, `Closing`, `Notices`, `Incidents`, `Summary`, `Fix.Kind` and `Fix.Refused` passed on warm `e23s5qw`; `Test.Fix.PartnerTurns` passed fresh. No shared-surface pin moved (no catalog key or count changed).
  - mutation: the approved branch of `Closed` made unreachable (`event = ..#APPROVED` -> `event = "never"`) -> `Test.Fix.PartnerDraft:TestStateNeverMoves` red ("an approval is told once", "told as a result that did not send", "with the kind's NOSTART as the reason"); and `Closed` also calling `Execute` on approved -> the same method red ("an approval is told once and sends no Execute"); each restored byte-identical (`cmp` against the saved copy), class green again.
  - Review patch: `TestStateNeverMoves` also pins the reason of the after-close final result (the executor's `UNUSABLE`), a sent final result (`result.partnerSent`, told as it came) and a progress result (told to nobody). mutation: `Closed`'s `ElseIf event '= FINISHED` made `ElseIf 0` (every event passes its notice through) -> `TestStateNeverMoves` red ("a result still in progress after the close tells nobody", "a rejection and an expiry after the close tell nobody and send no Execute"); and made `ElseIf 1` (every notice dropped) -> red ("a final result after the close is told once", "with the reason it came with", "a final result that sent after the close is told as it came"); each restored byte-identical (`cmp`), `Test.Fix.PartnerDraft` green again (10 methods).

**CI rework (iteration 3; CI run 42963531773 on 52db267d):**
- [x] [CI] `OcuTalon.Test.Data.Tables:TestContracts` fails in CI (iris (image), shard lane-b@Contract,Core,Data,Live): "the dry run keys (item, from, to and example since Story 23.2)". This story extended `Bridge.Data.ApprovalRequest` `DRYRUNKEYS` with `notice,recipients,simulated` (Code Map, AD-16) but did not move this shared-surface pin. Extend the pin additively to the parameter's full value (keep every earlier key and its order; message names Story 23.5's three keys); no product change. Demonstrated `mutation:` line.
  - Done (slot D): `Test.Data.Tables` `TestContracts` now pins `DRYRUNKEYS` at the parameter's full value (`...,example,notice,recipients,simulated`), its message naming Story 23.5's three keys; no product change. `Test.Data.Tables` passed (5 methods). `Test.Fix.DryRun` and `Test.Watch.GoodMessages` read RepairResend's own `DRYRUNKEYS`, and `Test.Fix.PartnerWarning` already pins the full value, so none needed a change.
  - mutation: `simulated` dropped from `ApprovalRequest` `DRYRUNKEYS` -> `Test.Data.Tables:TestContracts` red; restored byte-identical (`cmp`, `git status --short` and `git diff --stat` unchanged), class green again.



### Review Findings (rework iteration 1, smoke: code review)

Scope: the rework diff since `4e7cb8e7`. Four layers (blind, edge case, verification gap, acceptance); 6 findings: high 0, medium 0, low 5, false 1. Patched 2, rejected 4. Checklist: the `[Smoke]` item is fixed. The catalog holds 34 `incident.`/`result.` keys (28 plus this story's six), 34 + 6 core keys = 40 Delivery rows, TelegramOut handles 41, the operators are unchanged (no pin loosened), and `incident.partnerRequest` is an `approval` row as the product sends it.

- [x] [Review][Patch] (low) The WebChatOut drain guard waited for 40 web rows, but the answered Notification also records one (Notify sends any other kind to WebChatOut; `answered` is not a card kind), so one missing notice still passed and the last row could be written after the test ended [src/ocutalon/cls/OcuTalon/Test/Channel/TelegramChat.cls:522]. Now 41. The class passed warm, and the mutation above turns it red.
- [x] [Review][Patch] (low, Rule 19) The mutation line changed the test's own key filter, not the code under test. Closed in-pass: the catalog-side mutation above was applied, observed red, reverted and recorded.

Rejected (appendix):
- `TestNotices` sets the kind of `incident.partnerRequest` itself, so it cannot see the product's classification, and a future request key left off its list would pass as `incident` (verification gap, edge case): low. In this test the kind is fixture input: it pins that the channels record the kind they are given. The product's `approval` kind is pinned at `Test/Fix/PartnerDraft.cls:180`. Deriving the list from the product needs a new helper, which is more than a direct correction. Under Rule 19 this is acceptable: it is not an unfalsifiable pin of an AC.
- The spec's Shared surfaces list and `epic-23-context.md` do not name `TestNotices` (blind): low. The fix is a spec or context edit. Rule 19 already requires the implement stage to search the test trees for a shared surface's old shape.
- `followup_review_recommended: false` sits beside the Auto Run Result's "follow-up review recommended" (blind): low. The fix is a spec edit, and the scope of this re-review was set by the lead.
- The spec reads `status: done` while the tracker reads `review` (acceptance, process note): false as a defect. The implement stage sets the spec's status at finalize, and this review syncs the tracker.

### Review Findings (rework iteration 2, merge-time rulings: code review)

Scope: the rework diff since `931f0124` (DW-1109, DW-1108). Four layers (blind, edge case, verification gap, acceptance), launched with no model override (no `model-overrides.yaml`). 24 findings from the layers: high 0, medium 3, low 15, false 6. They group into 3 patched entries (5 findings), 1 deferred and ledgered entry (3 findings), and 16 rejected findings, plus one rejected check of this review's own. Checklist: (1) DW-1109 fixed: `Compute` skips MOVES 0 kinds only, an unregistered or missing kind still counts, the Guide change is that filter plus its doc line (AD-33 additive), and `TestPartnerRequestIsNotStepFour` is pinned with demonstrated mutations (one added here). (2) DW-1108 fixed per ruling 2(a): `Closed` tells one `result.partnerNotSent` with `PartnerWarning.NOSTART`, sends no Execute, adds no text, catalog key or schema. `Move` on an already closed incident does not re-run the close: `Closing` (summary build, summary notification) is called only from `Apply` on a move into closed, and `Move` stamps `ClosedAt` only when it is empty, which never happens on a real closed row. Nothing touches timers or the purge. `ResultKey(approved, Final 1, Completed 0, partner_warning)` gives `result.partnerNotSent` and `ResultSlots` gives `{reason}`, which Telegram and the phone render as text. On the web the result notice is a Delivery row only, and a closed incident's card is compact and shows no request, so the web offers no approve after the close. The Summary is frozen at the close, and the allowance counts sent mail, so the not-sent result touches neither. Approve after close sends no Execute, so no second (FixExecutor) result can follow and nothing is told twice. Re-review exit (Rule 15): no high, so the story closes.

- [x] [Review][Patch] (medium, Rule 19) The kind filter's pin ran only against repair rows with no `FixKind`. Production repairs carry a registered MOVES 1 kind, so a filter that skipped every registered kind would leave `Test.Demo.Guide` green and the demo's step 4 never done. Fixed: the repair row now has `FixKind` `repair_resend`, and the mutation line is under the DW-1109 item [src/ocutalon/cls/OcuTalon/Test/Demo/Guide.cls:190]
- [x] [Review][Patch] (low) The after-close final results were handed in with the row still `approved`. The executor closes the row (`failed` for a run that could not start, `done` for one that sent) before its FixResult comes. The test now sets those states first [src/ocutalon/cls/OcuTalon/Test/Fix/PartnerDraft.cls:427]
- [x] [Review][Patch] (low, Rule 14) Doc comments: `Closed` said it passes on only the executor's unusable result, but it passes on every final or interrupted result. The Guide bullet did not say that a request with no kind, or an unregistered one, still counts. The `TestStateNeverMoves` header did not list the sent result or the progress result [src/ocutalon/cls/OcuTalon/Watch/IncidentManager.cls:1729]
- [x] [Review][Defer] (medium) A partner request approved after the close stays `approved` for good. `Data.Purge.Keeps` then never purges its session, and a repeated approved outcome would be told again. This is DW-1108's residual: ruling 2(a) asked only for the telling, and ending the row needs a mechanism the spec does not give (no Execute is allowed). [src/ocutalon/cls/OcuTalon/Watch/IncidentManager.cls:1732] — deferred: DW-1117, routed owner=burndown, fix-risk med

Rejected (appendix):
- After approve-then-close, the result reads `UNUSABLE` ("couldn't read the approved fix") and not the kind's NOSTART (blind, acceptance): low. The window is the Execute's queue time between approve and the executor's start, and the ruling allows any existing reason. The fix changes `Executor.Unusable`, whose reasons another story specified, outside this rework.
- An interrupted result after the close has no test (blind): low. It is the same FINISHED event as the final result, whose branch is pinned by the `ElseIf 0` and `ElseIf 1` mutations.
- `Closed` repeats `Owns`, which `Event` already checked (blind): low. It costs one extra row open; passing the row through would widen `Aside`'s signature for no behaviour.
- The spec's frontmatter keeps `review_loop_iteration: 0` (blind): low. The fix is a spec edit.
- A closed incident with no `NoticedAt` tells nobody and logs nothing (edge): false. `Asked` raises a chat-asked request only on a noticed incident (`incident.NoticedAt '= ""`), so such a request cannot exist.
- `Move` stamps `ClosedAt` on a closed row that has none (edge): false for real rows. Every move into closed sets `ClosedAt` (`Closing` and `Move`), so only a hand-made row lacks it.
- A final result after a failed `FinishExecution` is told as `result.stillResending` (edge): low, theoretical. It needs the bridge's save to fail, and the open-incident path tells it the same way.
- A MOVES 0 kind without NOSTART would fall to Drop (edge): false today. `partner_warning` is the only MOVES 0 kind, and it has a NOSTART.
- The repeated approved outcome (edge): merged into the deferred DW-1117 (same root cause, the row is never ended).
- The fresh and reverse runs are not recorded (verification gap): false as a review defect. Rule 19's fresh check is the lead's gate before push.
- Spec line 31 (Boundaries), Decided in-stage 19, and the Code Map line on `finished` are not amended (verification gap, acceptance): low. The fix is a spec edit.
- The ask, close, approve sequence is built from fixtures, and PartnerNotice and SimMailbox rows are not asserted directly (acceptance): low. The stub host records no Execute, and nothing can be sent without one. Ruled the same way at the implement review.
- AD-15 is not annotated for the telling on a closed incident (acceptance): false as a violation. AD-15 refuses every move on a closed incident, and `Closed` moves nothing (state and variant are asserted unchanged). The telling is ruled (ruling 2a).
- `Demo.Guide` repeats `IncidentManager.Moves` inline (acceptance, Rule 2): low. The item prescribes this form, and `Moves` is Private on a production class. reopen_if: a second caller needs the MOVES test.
- DW-1108 and DW-1109 have no closing trailer (acceptance): false as a code defect. The lead appends those resolutions.
- The row stays approved, so the card still shows approved and the Telegram press text says "Sending" (acceptance): merged into DW-1117. The press text is existing text, and the ruling allows no new sentence.
- The web chat does not show the not-sent result (this review's own check): low. A closed card shows no request, so the web offers no approve after the close. Only a press already in flight while another channel closes the incident reaches it.

### Review Findings (rework iteration 3, CI: code review)

Scope: the rework diff since `6943545e` (commit `1d05b3fb`). Four layers (blind, edge case, verification gap, acceptance), launched with no model override (no `model-overrides.yaml`). 3 findings, all from blind: high 0, medium 0, low 3, false 0. Patched 0, deferred 0, rejected 3. Clean review. Checklist: the `[CI]` item is fixed. The `TestContracts` expected value equals `ApprovalRequest` `DRYRUNKEYS` character for character. It is the earlier 11 keys in their order plus `notice,recipients,simulated`, still a literal `$$$AssertEquals` (not loosened, not computed from the parameter), and its message names the three keys. The `mutation:` line is recorded under the item and in the Auto Run Result. Stale-pin sweep of `src/`: only `Test.Data.Tables:13` and `Test.Fix.PartnerWarning:103` pin this parameter, and both hold the full value. `Test.Fix.DryRun` and `Test.Watch.GoodMessages` read `RepairResend`'s own `DRYRUNKEYS`. No copy of the old 11-key string is left in tracked files outside `_bmad-output`. The reviewer re-ran `Test.Data.Tables` on slot D: 5 of 5 passed, with the slot's parameter confirmed at the 14-key value. Re-review exit (Rule 15): no high, so the story closes.

Rejected (appendix):
- The `## Verification` Shared surfaces line for `DRYRUNKEYS` names `Test.Live.Payloads` and `payloads.ts`, but not `Test.Data.Tables` or `Test.Fix.PartnerWarning` (blind): low. The fix is a spec edit. The pin is now moved and the sweep above finds no other stale pin. The same lesson was ruled the same way at iteration 1 (`TestNotices`).
- The iteration-3 Residual risks leave out that CI run 42963531773 also hit the DW-432 online-allowance flake (blind): low. The fix is a spec edit. The flake is already ledgered as DW-432, and the lead recorded this occurrence when it re-opened the story.
- The residual risk that slot D's `OcuTalon.Data.Turn` was reloaded gives no reason (blind): low. The fix is a spec edit. The reload only brought the dev slot in line with the branch. CI builds from source, and this review's own run of `Test.Data.Tables` on slot D passed.

## Spec Change Log

- 2026-11-11 (runner): lead smoke found the TelegramChat TestNotices shared-surface pin red; spec re-opened for rework iteration 1 with that [Smoke] item.
- 2026-11-11 (runner): Contest Planner merge-time rulings on DW-1109 (fix now; Demo/Guide.cls joins the AD-33 list) and DW-1108 (option (a), bounded at about 1 h); spec re-opened for rework iteration 2 with the two [Rework] items.
- 2026-11-11 (runner): CI red on 52db267d (Test.Data.Tables DRYRUNKEYS pin, story-class); spec re-opened for rework iteration 3 (the last under the cap) with that [CI] item.

- 2026-11-10 (runner): lead note before implement: 23.2 delivered (build on its code), More to try groups and count twelve, 37.2 interplay, spine lines written.

- 2026-11-10 (runner): More to try groups ruling recorded [AMENDED 2026-11-10, Contest Planner ruling].

- 2026-11-09 (runner): Contest Planner rulings on 23.5 recorded [AMENDED 2026-11-09, Contest Planner ruling]: three text edits, the no-open-incident answer, the web-chat condition replacing the residual, S6 for partner_warning; press.* keys in Catalog.Core.

## Review Triage Log

### 2026-11-10 - Review pass
- verdicts: 41 findings - high 0, medium 7, low 34, false 0, maybe-false 0 (routes: 7 patch, 2 defer, 32 reject)
- findings:
  - `[low]` `[patch]` (blind 1) EXPERIENCE.md "Items 4, 7 and 10 go to a card in the status rail" is wrong after the renumbering - fixed: the numbers are 5, 8 and 11 (Memory, Persona, Heartbeat), with an AMENDED marker
  - `[medium]` `[reject]` (blind 2) the 20-an-hour cap is checked at ask time only - by design: Decided 4 (checked at ask, the overshoot bounded by the fixture's contact count) and Decided 5 (a copy per recipient session)
  - `[medium]` `[defer]` (blind 3) a pending partner request does not block closing, and an approval after the close is dropped - spec-bound (Aside refuses on closed); deferred with what would settle it
  - `[low]` `[reject]` (blind 4) summary.partnerSent reads the same for a partial send - the ruled text has no partial summary key and the fixture holds one contact, so a partial send cannot occur
  - `[low]` `[reject]` (blind 5) the draft input holds the stored cause - the spec's Always list names "the stored plain cause" as an input, normalised to one line
  - `[low]` `[reject]` (blind 6) "20" is written into three texts - the ruled text; EMAILLIMIT is 20 and a change to it is a text change
  - `[low]` `[reject]` (blind 7) Executor.Run ignores Ready's return - only PartnerWarning implements it and sets a reason whenever it answers 0; no reachable failure
  - `[low]` `[reject]` (blind 8) item is optional for every kind - an empty item reaches the kind's dry run, which refuses it plainly (the same refusal as an unknown item)
  - `[low]` `[reject]` (blind 9) a draft for a missing or closed incident ends silently - the spec says "A missing or closed incident is left alone", and the already-asked case is the ruled Type 4 line
  - `[low]` `[patch]` (blind 10) comments of Msg.Command.ProposeFix and Part.IncidentRequest still list three kinds - fixed
  - `[medium]` `[reject]` (blind 11) no evaluation case for the new Chat line - the eval cases that run the real model belong to the release evaluation, which this story only extends through S6 (AC-S6P, patched below as a test of the tally)
  - `[low]` `[reject]` (edge 1) Run ignores Ready's return - as blind 7
  - `[low]` `[reject]` (edge 2) an exception inside Deliver after some copies were saved ends the run as could-not-read - Deliver returns statuses and does not throw for its reads; theoretical
  - `[medium]` `[reject]` (edge 3) no allowance check at send time - as blind 2 (Decided 4)
  - `[low]` `[reject]` (edge 4) MailAllowed's retryAt for more than 1 is the oldest row's - only the ask passes more than 1, with one fixture contact; theoretical
  - `[low]` `[reject]` (edge 5) OnPartnerNotice takes an empty ApprovalRef or Text - the only sender is the Executor, which builds both from the approved row; theoretical
  - `[low]` `[reject]` (edge 6) a second ask before the first raise starts a second draft - by design, Decided 7 and the matrix row "Already asked" (one Type 4 line)
  - `[low]` `[reject]` (edge 7) a draft for a closed incident ends with no notice - as blind 9
  - `[medium]` `[defer]` (edge 8) approved partner request on a closed incident - as blind 3
  - `[low]` `[reject]` (edge 9) item and production names go into the draft input without Normalise - they are configuration names of the production, not message text, and the spec lists them as inputs
  - `[low]` `[reject]` (edge 10) a skipped contact whose address changed reads "no longer a contact" - one fixture contact, so the position cannot move; theoretical
  - `[low]` `[reject]` (edge 11) item optional for the item kinds - as blind 8
  - `[medium]` `[patch]` (gap 1) OnResponse and OnError of a Draft were never exercised, only Drafted - fixed: probe seams DraftAnswered and DraftRefused and Test.Fix.PartnerDraft:TestDraftCompletionRouting; mutation line written
  - `[low]` `[reject]` (gap 2) Deliver with two recipient sessions and one failed copy is untested - demo mode's owner is one session; reopen_if a second recipient session can hold a partner request
  - `[low]` `[patch]` (gap 3a) AC-NOOPEN has no mutation line - fixed (demonstrated red on Test.Watch.Tools)
  - `[low]` `[patch]` (gap 3b) AC-NOTDRAFTED-WEB has no mutation line - fixed (demonstrated red on Test.Core.WebChatOut and chat-view.test.mjs)
  - `[medium]` `[patch]` (gap 3c) AC-S6P has no pinning test or line - fixed: Test.Eval.Report:TestPartnerRequestIsCounted, with a demonstrated mutation
  - `[low]` `[reject]` (gap 3d) AC15's recorded mutation went red in a source-text test, not K9c - K9c runs in the browser units; reopen_if a regression of the press passes both tests
  - `[low]` `[reject]` (gap 3e) AC4, AC6, AC11 and AC14 name different red tests than the spec's tasks - each line names a test that went red on its mutation; the trim of AC4 is a no-op on a normalised text (recorded)
  - `[low]` `[reject]` (gap 4a) TestDemoModeOffKeepsTheNotice waits CACHESECONDS + 2 - the wait is the setting cache's expiry (Decided 20), not a guess about a job
  - `[low]` `[reject]` (gap 4b) timed negative checks and a wall-clock bound in PartnerTurns - the bound is the spec's own (20 s) against a measured 0.4 s; the absence checks wait far longer than the draft takes
  - `[low]` `[patch]` (gap 4c) TestAskedTurnRaisesWithinBounds reports the measurement with $$$AssertSkipped, so the method reads skipped on every pass - fixed: $$$LogMessage
  - `[low]` `[reject]` (gap 4d) Test.Fix.Refused's comment says nothing is sent to a mailbox, with no SimMessage assertion - the no-run assertions (no FixRun, row unchanged) hold it
  - `[low]` `[reject]` (gap other 1) Kind.ProductionName swallows a failed read of the production list - falls back to the class name by design (Decided in-stage); no reachable wrong send
  - `[low]` `[reject]` (gap other 2) MailAllowed's more argument is unobservable with one contact - covered by the Test.Core.Allowance unit case
  - `[low]` `[reject]` (intent 1) a notice goes to every recipient session, the allowance counts the asker - Decided 4 and 5
  - `[low]` `[reject]` (intent 2) a local install never reaches a draft (no contacts) - ruled: contacts are demo-only (the partner-contacts ruling)
  - `[low]` `[reject]` (intent 3) some ruled texts do not name the mailbox - the texts are the Planner's, verbatim; none says or implies a real email
  - `[low]` `[reject]` (intent 4) new persistent message classes - the spec's veto list names Fix.Msg.PartnerNotice and Watch.Msg.Draft; no table or column is new
  - `[low]` `[reject]` (intent 5) EXPERIENCE.md numbers rewritten - the ruling of the More to try groups requires it
  - `[low]` `[reject]` (intent 6) no single browser test runs ask, card and mailbox - PartnerTurns (production) and A13 (card over HTTP) pin the halves; Decided 20

### 2026-11-10 - Review pass (rework iteration 1, smoke)
- verdicts: 8 findings - high 0, medium 0, low 6, false 2, maybe-false 0 (routes: 0 patch, 0 defer, 8 reject)
- findings:
  - `[low]` `[reject]` (blind 1) the pins are hand-kept literals that break again when the catalog grows - they are the deliberate pins the item asks to update (deriving them from the key list would make the count assertion tautological); fix is more than a direct correction
  - `[low]` `[reject]` (blind 2) the test's own `approval` list means it cannot see the product's classification of `incident.partnerRequest` - true, the implementer saw the mutation stay green and did not record it as a pin; the same holds for the other seven request keys and the product kind is pinned at `Test/Fix/PartnerDraft.cls:180`
  - `[false]` `[reject]` (blind 3) no sweep for other tests pinning the Watch catalog counts - the verification-gap layer searched `src/ocutalon/cls/OcuTalon/Test` and found no other pin of the old 28 or 34; `Test.Msg.Catalog` already holds fixtures for all six keys
  - `[false]` `[reject]` (blind 4) `review_loop_iteration` and `followup_review_recommended` unchanged around the rework - the counter counts bad_spec loopbacks (none here) and the recommendation is recomputed at finalize
  - `[low]` `[reject]` (gap 1) the `approval` clause for `incident.partnerRequest` cannot fail in `TestNotices` - same claim and same evidence as blind 2: pinned in `PartnerDraft.cls:180`, no named harm
  - `[low]` `[reject]` (gap 2) the mutation edits the test's own filter, not the product - it shows the count pins go red; a product-side removal of a key would also move 34 to 33 (the layer checked the count), so the pin reacts to the product as well
  - `[low]` `[reject]` (gap other) the literals 34, 40, 41, 40 are hand-maintained - same as blind 1
  - `[low]` `[reject]` (intent 1) the kind list is hand-coded in the test, not derived from the product - same as blind 2

### 2026-11-11 - Review pass (rework iteration 2, merge-time rulings)
- verdicts: 23 findings - high 0, medium 1, low 20, false 2, maybe-false 0 (routes: 4 patch, 19 reject)
- findings:
  - `[low]` `[reject]` (blind 1) an approved request on a closed, never-noticed incident is still dropped (Move tells only when NoticedAt is set) - Aside has the same contract; a partner request is raised on a noticed incident, so no session is waiting on an unnoticed one.
  - `[low]` `[reject]` (blind 2) the request row stays approved after the not-sent telling - ending the row needs a new lifecycle call, outside the ruled item; it stayed approved before this change too.
  - `[low]` `[reject]` (blind 3) the Telegram press answer still says it is sending - existing text; the ruling allows no new sentence, and result.partnerNotSent follows it.
  - `[low]` `[reject]` (blind 4) the MOVES test is repeated in Demo.Guide - the lead's item fixes this form (resolve the class through Fix.Kind as Moves does, additive in Guide only); Moves is Private on the production class and a shared helper would touch Fix/Kind.cls.
  - `[low]` `[patch]` (blind 5) test gaps: the after-close final result's reason is not asserted, a progress result after the close is not tested - added to TestStateNeverMoves (the UNUSABLE reason, a sent result, a progress result); the unregistered-kind branch and the Drop line stay unpinned (pre-existing contract, existing rows have no FixKind), rejected.
  - `[low]` `[reject]` (blind 6) review_loop_iteration and followup_review_recommended in the frontmatter - the fix is a spec edit by the lead.
  - `[low]` `[reject]` (edge 1) Move stamps ClosedAt on a closed row that has none - only a legacy row; the stamp is the right close time and changes no state.
  - `[low]` `[reject]` (edge 2) the row stays approved and a repeated approved outcome re-tells - same as blind 2; the outcome is told once per approval.
  - `[low]` `[reject]` (edge 3) a MOVES 0 kind without the partner reason or key - theoretical: the only such kind is partner_warning; a second one carries its own NOSTART.
  - `[low]` `[reject]` (edge 4) a rejected or expired partner request after the close gets only the Type 4 line - the ruling names the approved event; the answer to a rejection is not the user's lost send.
  - `[low]` `[reject]` (edge 5) distinct Drop reasons per branch - cosmetic.
  - `[false]` `[reject]` (edge 6) earlier partner rows in the loop mask a later state - a regression in the filter turns the first iteration red already; the rows only accumulate.
  - `[false]` `[reject]` (edge 7) the claim that the incident is unchanged while Move re-saves and re-publishes it - Move saves only a changed row and the incident event is the one Aside always sends; state and variant are asserted unchanged.
  - `[medium]` `[patch]` (gap 1) the kind filter has no test on the fixApproved side (finished) - added to TestPartnerRequestIsNotStepFour; a mutation that filters only answered turns it red.
  - `[low]` `[patch]` (gap 2) Closed's refusal and passthrough branches have no mutation line and the sent and progress results no test - tests added, two mutation lines recorded under the item.
  - `[low]` `[reject]` (gap 3) the unregistered-kind branch is pinned only by existing rows without FixKind - those rows are the pin; the lead's item states the behaviour.
  - `[low]` `[reject]` (gap 4) rejected and expired assertions held before the change - they guard against over-telling in Closed, which the ElseIf mutation now shows.
  - `[low]` `[reject]` (intent 1) the test builds the closed incident and calls OnRequest on the stub host, not the ask-close-approve chat sequence - the closed-incident fixtures of TestStateNeverMoves are the named place.
  - `[low]` `[reject]` (intent 2) no PartnerNotice or SimMailbox row is asserted directly - none can exist without an Execute, which the stub host records as sent none.
  - `[low]` `[patch]` (intent 3) the after-close final result's reason differs from NOSTART and is not asserted - the executor's UNUSABLE reason is now asserted; it reads as "couldn't read the approved fix", existing text.
  - `[low]` `[reject]` (intent 4) the Telegram press answer is untouched - same as blind 3.
  - `[low]` `[reject]` (intent 5) Move re-emits the incident event - same as edge 7.
  - `[low]` `[reject]` (intent 6) the result notice replaces the answered notice for an approval on a closed incident - the intended telling (one result, not two).

### 2026-11-11 - Review pass (rework iteration 3, CI)
- verdicts: 3 findings - high 0, medium 0, low 3, false 0, maybe-false 0
- findings:
  - `[low]` `[reject]` (blind 1) the full `DRYRUNKEYS` string is hard-coded in `Test.Data.Tables` and `Test.Fix.PartnerWarning` - the shared-surface rule is a literal, never loosened or computed pin; the second pin is the story's own, and merging them is more than a direct correction.
  - `[low]` `[reject]` (blind 2) no green CI re-run is recorded - the re-run follows the lead's push, which this pass never makes; the item asks for the pin and a mutation, both recorded.
  - `[low]` `[reject]` (blind 3) the Done line is thinner than its neighbours - it names the pins checked and the result; more detail adds nothing to an oversized spec.
- edge-case, verification-gap and intent-alignment layers: no findings (the intent-alignment report is descriptive: the diff touches the contract surface of the intent's `DryRun {notice, recipients, simulated}`, and the behaviours are pinned by classes this pass does not touch).

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

8. Implement stage: the registry id and the Features id are `partnerWarning` (the spec's name for both), the one row the groups ruling calls warnPartner, in `Incidents and fixes` after `reroute`. EXPERIENCE numbers it Item 3 and the items after it one higher; README line 40 and the header say twelve.
9. Implement stage: the Action entry's target is "<n> partner contact(s) (<contact ids>) of <production class name> (simulated)": the audit shape has no field for the ids, so they sit in the target text, and no address is in it.
10. Implement stage: `Fix.Kind.ProductionName` answers the class name when `Reader.Admits` throws (a namespace whose production list can't be read, such as a slot with no OcuTalon.Production), so that Facts and the reasons never fail on it.
11. Implement stage: `Channel/SimMailbox/Out` now sets `SimMessage.ApprovalRef` on a partner notice (`Keep` records the Ref on the Delivery row only), because `Ownership.PartnerNotices` counts the SimMessage rows with an ApprovalRef; `OnPartnerNotice` answers an error status for an owner that is not a session, so that `Executor.Deliver` never counts such a copy as sent. The ApprovalRef and a mailbox Delivery row do not clash with the phone's or Telegram's lookups (they are by channel).
12. Implement stage: a delay notice is not a fix of the failure. `Watch.Summary` gives its runs their own end lines but does not set "a fix ran", so an incident whose only run was a notice still says `summary.noFixRan`, and the message counts are the repair's alone.
13. Implement stage: `incident-view.ts` gives no fix sentence and no fixing line for a pending or running `partner_warning` request (`aboutFix`), which would otherwise read the diagnosis's "I can repair and resend ..." on a resolved incident that only waits for the notice.
14. Implement stage: `PartnerWarning.Normalise` strips the same invisible characters as `Msg.Catalog.Clean` (a private method of another area), so that a model text cannot hide a bidirectional control between the card and the mailbox.
15. Implement stage: `IncidentManager.Start` and `StartDraft` share `SendToSelf`; the draft that finds a request of its kind waiting by its end writes one Type 4 line and tells nobody (no `result.partnerNotDrafted`), because another draft already succeeded.
16. Implement stage: `propose_fix`'s `item` argument is optional (default ""), so a partner warning is called with the kind alone; for `partner_warning` the tool answers `refused` with the ruled NOWARNING sentence when the session has no incident that is not closed, and finds incidents in every state but closed (`WARNABLE`).
17. Implement stage, names that differ from the spec: the press tests of 23.2 and this story are in `Test.Channel.TelegramApproval` (there is no TelegramIn press unit); `Test.Fix.Asked` now reads the failed-ask warning from `RaiseAsked` (the extracted tail), not `Asked`; `ExecutorProbe.SendNotice` and the draft seams of `IncidentProbe` (`StartDraft`, `SendDraft`, `BeginDraft`, `EndDraft`, `FactsNow`) are the test seams.
18. Implement stage: a switch of demo mode reaches a production job only after `Data.Setting`'s 60-second per-process cache expires, so a notice approved within a minute of switching demo mode off can still be delivered, and a switch on is as slow; `TestDemoModeOffKeepsTheNotice` waits 62 seconds for that reason.
19. Implement stage, residual (an intent gap for the Planner, Lane B, not in the AD-33 list): `Demo.Guide.Compute` counts any answered or approved request of the guide's incident for step 4 and for the finish, partner requests included. The finish still needs the incident `resolved`, so a partner request never finishes the guide, but a partner request approved while the repair still waits would mark step 4 as done. `Demo/Guide.cls` is unchanged.
20. Implement stage: AC15's browser case (`K9c`) pins that the item sends its prompt once as the user's own message; the card and the mailbox after approval are pinned on the production by `Test.Fix.PartnerTurns` and by `A13` (the card, over real HTTP), not by one browser run of the whole path.

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
- Estimate recorded (2026-11-10, lead, before implement): the `result.partnerNotDrafted` web card is about 0.75 h, under the one-hour bar, so it is built (not an intent gap). The seam: `Channel/WebChat/Out.cls` `ToolCallCard` takes this one key without an ApprovalRef onto the card path (the `recentNotices` read already keeps a `result` row that has a ChannelMessageId, so the snapshot needs no change); `web/src/app/chat/chat-view.ts` `noticeOf` shows a `result` with no approvalRef only when it carries a `ref` (an incident-card `result` Delivery row has none, so it stays the incident card's); `web/scripts/chat-view.test.mjs` lines 119 and 397 pin the old shape and are updated; one IRIS test in `Test/Core/WebChatOut.cls` (sibling `TestToolCallCards`) and the `chat-view.test.mjs` case pin it.

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
  - Classes: `Channel/SimMailbox/Out.cls`, `Data/SimMessage.cls` (doc), `Core/Allowance.cls`, `Data/Ownership.cls` (new query), `Live/Payload/Approval.cls`, `Live/Payload/Part/DryRun.cls`, `Live/Payload/Incident.cls` (if needed), `Demo/Features.cls`. `Demo/Guide.cls` (the one-line kind filter for step 4) [ADDED 2026-11-11, Contest Planner merge-time ruling 1 on DW-1109 (prompts/epic-23-rulings-235.md)]
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
- Added by the implement stage (each updated in the same pass): `Test.Fix.Asked` (the failed-ask warning's source method is `RaiseAsked`), `Test.Fix.ExecutorProbe` and `Test.Watch.IncidentProbe` (the notice and draft seams), `Test.Msg.Catalog`'s OneForms block and its web-wording rule, `Test.Core.WebChatOut` (the not-drafted card), `Test.Live.Payloads`'s DryRun contract, `Test.Demo.Guide`, `Test.Channel.TelegramApproval`, `Test.Install.SecurityOverview`'s kind rows, `web/scripts/{chat-view,chat-announcements,playwright-projects,more-to-try-view,more-to-try-sources,ux-strings}.test.mjs`, and EXPERIENCE.md's item numbers.

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

**Recorded by the implement stage (2026-11-10/11):**
- Task 0 (fresh throwaway `e23s5i`, `Test.Fix.PartnerTurns` first case, the CI mock): the request was raised 0.25 s after the asking turn ended and 0.39 s after it began; the draft's Decide timer never fired (no fallback `timeout`). Under the 20 s bound.
- Runs: every class of the warm loop passed on `e23s5iw` (`Test.Fix.PartnerWarning`, `PartnerDraft`, `Kind`, `Refused`, `Asked`, `Executor`, `ItemKinds`, `Test.Watch.Summary`, `Transitions`, `Notices`, `Incidents`, `Test.Core.Allowance`, `WebChatOut`, `Test.Demo.Features`, `Guide`, `SimMailboxOut`, `SimMailboxIn`, `Test.Msg.Catalog`, `Test.Install.SecurityOverview`, `Test.Live.Payloads`, `Test.Channel.TelegramApproval`, `Test.Agent.Constants`, `Instructions`, `Test.Watch.Tools`, `Test.Bridge.CodeRules`); `Test.Fix.PartnerTurns` passed fresh (`e23s5i`); `live:cards` (30 passed, A13 included) and `live:sign-in-3 --part 1/2` (127 passed, K9c and K27 included) passed; `node --test web/scripts/*.test.mjs`, `npm --prefix web run lint`, `bash docker/tests/test-{boundaries,readme,ci-config,mock,storage,class-rules,ci-changes}.sh` passed.
- Mutations (applied, red observed, reverted byte-identical: `git status --short` and `git diff` hash unchanged):
  - mutation: add `incident.SampleError` to `Facts` -> `Test.Fix.PartnerWarning:TestFacts` red (AC1)
  - mutation: `AskedSlots` gives `recipients` empty -> `Test.Fix.PartnerDraft:TestDraftRaised` and `TestNoticeKeys` red (AC2)
  - mutation: `Plan` skips the address test of `Recheck` -> `Test.Fix.PartnerWarning:TestRecheck` red (AC3)
  - mutation: `OnPartnerNotice` cuts the text at 900 characters (a trim shows no difference on a normalised text, so the cut stands in for it) -> `Test.Fix.PartnerWarning:TestApprovedNoticeIsSentByteForByte` red (AC4; `Test.Fix.PartnerTurns` reads the same text from the mailbox, not run mutated)
  - mutation: `Aside` also calls `Execute` on rejected -> `Test.Fix.PartnerDraft:TestStateNeverMoves` red (AC5)
  - mutation: `Ready` always 1 -> `Test.Fix.PartnerWarning:TestDemoModeOffKeepsTheNotice` red (AC6; not run mutated on the production)
  - mutation: `AskedDraft` skips the `NOCONTACTS` check -> `Test.Fix.PartnerDraft:TestRefusals` red (AC7)
  - mutation: `READONLYPROPOSEFIX` 1 -> `Test.Fix.PartnerTurns:TestInjectedTurn` red on a fresh stack (AC8)
  - mutation: `Event` routes partner events through `Apply` -> `Test.Fix.PartnerDraft:TestStateNeverMoves` red (AC9)
  - mutation: `MailAllowed` counts incoming emails only -> `Test.Core.Allowance:TestMailAllowedCountsPartnerNotices` red on the warm stack (AC10)
  - mutation: `OnPartnerNotice` omits `Announce` -> `Test.Demo.SimMailboxOut:TestPartnerNotice` red (AC11; not run mutated on the production)
  - mutation: `Drafted` skips `NotDrafted` -> `Test.Fix.PartnerDraft:TestDraftFails` red (AC12)
  - mutation: `RunEvents` uses the counts line for a partner run -> `Test.Watch.Summary:TestPartnerLines` red (AC13)
  - mutation: `Live.Payload.Approval.FromRow` drops `Notice` -> `Test.Live.Payloads:TestApprovalPartnerNotice` red (AC14; `approval-card.spec.ts` A13 reads the same fields in CI)
  - mutation: the More to try `partnerWarning` press sends nothing -> `more-to-try-sources.test.mjs` (the four prompts of the outbox) red (AC15; `K9c` in CI)
  - mutation: `result.partnerSent` reads "sent by email" -> `Test.Msg.Catalog:TestPartnerTextsNameTheSimulatedMailbox` red (AC16)
  - mutation: `OnError` of a Draft request quits with the error instead of calling `Drafted` -> `Test.Fix.PartnerDraft:TestDraftCompletionRouting` red (AC12's error case, through the framework's completion handler)
  - mutation: `WatchTools.ProposeFix` never maps no_incident to NOWARNING for a partner_warning -> `Test.Watch.Tools:TestProposePartnerWarning` red (AC-NOOPEN)
  - mutation: `WebChat.Out.ToolCallCard` drops the clause for `KEYPARTNERNOTDRAFTED` -> `Test.Core.WebChatOut:TestPartnerNotDraftedCard` red; `bareResult` in `chat-view.ts` forced false -> `web/scripts/chat-view.test.mjs` red (AC-NOTDRAFTED-WEB)
  - mutation: `IncidentManager.Asked` stops refusing a session that is not a recipient (the eval session) -> `Test.Eval.Report:TestPartnerRequestIsCounted` (and `TestRaisedFixRequestIsCounted`) red (AC-S6P)

**QA stage (2026-11-10; (QA) marks what it added; fresh tag `e23s5q`, warm tag `e23s5qw`):**
- (QA) `src/ocutalon/cls/OcuTalon/Test/Fix/PartnerWarning.cls`, two methods added (warm, no production):
  - `TestNoticeTextIsNeverAltered` (AC4): a notice with diacritics, an en dash, CJK, a check mark, a percent sign, template-like braces, markup, quotes and a backslash reaches the mailbox as the mail's Text character for character and byte for byte. An emoji (above U+FFFF) is left out: `Fix.Kind.PartnerWarning.Normalise` does not keep it, so a drafted notice never holds one (inference, not measured separately).
    - mutation: `OnPartnerNotice` replaces the en dash with a hyphen -> `Test.Fix.PartnerWarning:TestNoticeTextIsNeverAltered` red (the older `TestApprovedNoticeIsSentByteForByte` stays green on that change; reverted, green again on the same warm stack)
  - `TestClassTextsClaimNoRealEmail` (AC16): the texts that live in classes (the kind's NOTSETUP, NOCONTACTS, NOITEM, ALLOWANCE, RECHECK and NOSTART, `IncidentManager` MESSAGEDRAFTING and `WatchTools` NOWARNING) hold no phrase that says or implies a real email was sent.
    - mutation: `PartnerWarning` NOSTART reads "... the delay notice by email" -> `Test.Fix.PartnerWarning:TestClassTextsClaimNoRealEmail` red (reverted, green again)
- (QA) `web/e2e/chat/notice.spec.ts`, case `N21` added (AC-NOTDRAFTED-WEB, in the browser): a `result.partnerNotDrafted` Notification through the real NoticesIn, Notify and WebChatOut shows as a notice card of the chat with the ruled text, the info icon, no heading, strip or button, and again after a reload. Run locally after `ci/iris.sh build`: `OCUTALON_LIVE_DEADLINE=1500 ci/iris.sh live sign-in --part 5/12` (the part that holds `chat/notice.spec.ts`; 21 passed, N21 included).
  - mutation: `Channel.WebChat.Out.ToolCallCard` without the `KEYPARTNERNOTDRAFTED` clause -> `notice.spec.ts` N21 red on a fresh stack (20 passed, 1 failed; reverted, the tree is byte-identical)
- QA runs: `OcuTalon.Test.Fix.PartnerWarning` passed on the warm stack (13 methods); `node --test web/scripts/*.test.mjs` 1830 pass; `npm --prefix web run lint`; `bash docker/tests/test-{boundaries,class-rules,ci-config,readme}.sh` pass. `ci/units.sh` is unchanged.
- **Code review (2026-11-11; warm tag `e23s5cw`, fresh tag `e23s5c`).** Each mutation was applied, the red observed and reverted, and `git status --short` and the `git diff` hash checked identical. The class was then green again on the same warm stack.
  - mutation: `Executor.Run` skips `AsApproved` -> `Test.Fix.PartnerWarning:TestTamperedRowSendsNothing` red (AC4, AC8: only the approved text is sent)
  - mutation: `Plan` names an unknown target "Partner contact {id}" again -> `Test.Fix.PartnerWarning:TestRecheck` and `TestTamperedRowSendsNothing` red (AC3, Public Text)
  - mutation: `PartnerWarning` without `NOREAD` -> `Test.Fix.PartnerWarning:TestContract` and `TestClassTextsClaimNoRealEmail` red
  - mutation: `Summary.RunEvents` writes `summary.fixStarted` for a contact run -> `Test.Watch.Summary:TestPartnerLines` red (AC13)
  - mutation: `Drafted` without its closed-incident guard -> `Test.Fix.PartnerDraft:TestDraftFails` red
  - mutation (AC15, corrects the line above): the `partnerWarning` press sends nothing -> `web/e2e/guide/more-to-try.spec.ts` K9c red in `ci/iris.sh live sign-in-3 --part 1/2` on a rebuilt bundle (126 passed, 1 failed: K9c only). The bundle was reverted and rebuilt.
  - Runs: warm, every class passed: `Test.Fix.PartnerWarning`, `PartnerDraft`, `Kind`, `Refused`, `Asked`, `Executor`, `ItemKinds`, `Test.Watch.Summary`, `Incidents` and `Test.Demo.Guide`. Fresh: `Test.Fix.PartnerTurns` passed (143.5 s, with the added 62 s wait). `ci/iris.sh live cards`: 30 passed, A13 included, with its new mailbox control. Also passed: `node --test web/scripts/*.test.mjs` (1830 pass), `npm --prefix web run lint`, and `bash docker/tests/test-{boundaries,readme,class-rules}.sh`.
- QA reads, no change needed: AC14's A13 already uses the `request` fixture (own cookie jar, never `page.request`) as the `OcuTalonUser`-only fixture user with a second-session check (404 and still pending); AC-NOOPEN is pinned by `Test.Watch.Tools:TestProposePartnerWarning` and `Test.Fix.PartnerTurns:TestSecondSessionAsks`; AC-S6P by `Test.Eval.Report:TestPartnerRequestIsCounted`; the allowance count by `Test.Core.Allowance:TestMailAllowedCountsPartnerNotices`; the web texts by `approval-view.test.mjs` ("never says or implies that a real email was sent").

## Auto Run Result

Status: done
Blocking condition: none

Summary: `partner_warning` is a new fix kind asked for in the chat through `propose_fix`. IncidentManager has the notice drafted through Decide from code-built facts (an untrusted, fresh turn that can act on nothing), raises one `fix` request whose dry run holds the exact text and every recipient from the demo-only fixture `Fix.PartnerContacts`, and, after approval, FixExecutor re-checks the recipients and sends the approved text byte for byte through `SimMailboxOut` (never `EmailOut`). With demo mode off at run time the approved notice is kept as a draft with the ruled line. A partner request never moves the incident's state. A failed draft reaches the web chat as a notice card.

Files changed: see the diff since baseline `10f53487e894b7bc8e5f01489ee28aa8dc336f4f`. New: `Fix/Kind/PartnerWarning.cls`, `Fix/PartnerContacts.cls`, `Fix/Msg/PartnerNotice.cls`, `Watch/Msg/Draft.cls`, five CI mock scenarios, `Test.Fix.PartnerWarning`, `PartnerDraft`, `PartnerTurns`. Extended: Fix Kind and Executor, IncidentManager, Notice, Summary, Allowance, Ownership, SimMailbox and WebChat out, Telegram In, the Watch and Core catalogs, WatchTools, Chat, the approval and incident payloads, the web approval card, rail, incident view, chat view and More to try (twelve items), README, EXPERIENCE.md, `docs/security-overview.md`, and the shared-surface tests. `ci/units.sh` is unchanged.

Review: 41 findings from four layers. Patched: 7 (2 medium: the draft completion handlers had no test, AC-S6P had no test; 5 low: the EXPERIENCE.md item numbers, two stale doc comments, two missing mutation lines, one skipped-status test). Deferred: 2 (both medium: approve-after-close of a partner request; the guide's step 4 counting a partner request). Rejected: 32, each with its reason in the triage log.

Verification: node tests 1830 pass; lint; `test-boundaries`, `test-readme`, `test-ci-config`, `test-mock`, `test-class-rules` pass. The spec's warm loop (Fix.PartnerWarning, PartnerDraft, Kind, Refused, Watch.Summary, Core.Allowance, Demo.Features, Guide, SimMailboxOut, Msg.Catalog, Install.SecurityOverview, Live.Payloads, TelegramIn, Agent.Constants, Watch.Tools, Core.WebChatOut, Eval.Report, Fix.Asked, Executor, Watch.Incidents, Notices, Transitions) passed on `e23s5iw`; `Test.Fix.PartnerTurns` and `Test.Demo.SimMailboxIn` passed fresh on `e23s5i`. Browser: `live:cards` (A13) and `live:sign-in-3 --part 1/2` (K9c) passed in the implement pass. The `partnerNotDrafted` web card was estimated at 0.75 h and built.

Residual risks: the two deferred items above; the review-pass tests (`TestDraftCompletionRouting`, `TestPartnerRequestIsCounted`) and the probe seams were not re-reviewed (follow-up review recommended: two medium patches on a first pass). The browser units for AC14/AC15 and `ci/checks.sh` are left to CI.

### Rework iteration 1 (smoke)

Summary: `Test.Channel.TelegramChat:TestNotices` pinned the Watch notice keys at 28 and the Delivery rows at 34. The catalog now holds 34 `incident.`/`result.` keys (this story added `incident.partnerRequest` and the five `result.partner*` keys), so the pins are now 34 keys, 40 Delivery rows, 41 notifications handled by TelegramOut (the 40 and the answered one) and 40 web rows; `incident.partnerRequest` joins the `approval` rows. No product change.

Files changed: `src/ocutalon/cls/OcuTalon/Test/Channel/TelegramChat.cls` (the pins and the `approval` list); this spec (item ticked, mutation line, triage entry).

Review: 8 findings from four layers (one returned none). Patched 0, deferred 0, rejected 8 (6 low, 2 false), each with its reason in the triage log. Follow-up review recommended: false (no `high` patched on this follow-up pass).

Verification: `Test.Channel.TelegramChat` passed in full on warm stack `e23s5rw` (slot D), and again after the mutation was reverted; `test-boundaries` and `test-class-rules` pass. mutation: see the Smoke item.

Residual risks: `TestNotices` classifies the request keys itself, so the `approval` kind of `incident.partnerRequest` is pinned by `Test.Fix.PartnerDraft` and not by this class (as for the other request keys).

### Rework iteration 2 (merge-time rulings)

Status: done
Blocking condition: none

Summary: DW-1109 and DW-1108 are done. `Demo.Guide.Compute` leaves a request whose kind never moves the incident (`MOVES` 0; an unregistered kind still counts) out of step 4 and the finish. `IncidentManager.Aside` hands a closed incident to the new `Closed`: an approved MOVES 0 request tells its recipients `result.partnerNotSent` with the kind's `NOSTART` (existing text), sends nothing (no Execute, no PartnerNotice, no SimMailbox row) and leaves the incident closed; the final result of an approve-then-close request is told as it came (`UNUSABLE` reason); other events are still refused with the Type 4 line. No new text, no catalog or schema change (about 0.5 h). Both `deferred:` entries are removed from the frontmatter.

Files changed: `Demo/Guide.cls`, `Watch/IncidentManager.cls`, `Test/Demo/Guide.cls` (`TestPartnerRequestIsNotStepFour`), `Test/Fix/PartnerDraft.cls` (`TestStateNeverMoves`, closed part); this spec.

Review: 23 findings from four layers. Patched 4 (1 medium: the filter's finished side had no test; 3 low: the after-close reason, a sent result and a progress result had no assertions, and the refusal and passthrough branches no mutation line), deferred 0, rejected 19 (17 low, 2 false), each with its reason in the triage log. Follow-up review recommended: false (this follow-up pass patched no `high`).

Verification: `Test.Demo.Guide` (26 methods) and `Test.Fix.PartnerDraft` (10) passed on slot D after the patches; before them, on slot D and warm `e23s5qw`: `Test.Fix.PartnerWarning`, `Test.Watch.Transitions`, `Closing`, `Notices`, `Incidents`, `Summary`, `Fix.Kind` and `Fix.Refused` passed (one slot-D `Test.Watch.Summary:TestProductionName` environment error, "Item Decide not found in Production", passed warm), and `Test.Fix.PartnerTurns` passed fresh. `test-boundaries` and `test-class-rules` pass. mutation: see the two items (four mutations, each red and reverted byte-identical).

Residual risks: the request row of a partner notice approved after the close stays `approved` (ending it needs a lifecycle call outside this item); the Telegram press answer still says it is sending, and `result.partnerNotSent` follows it; the after-close final result reads "OcuTalon couldn't read the approved fix" (existing text).

### Rework iteration 3 (CI)

Status: done
Blocking condition: none

Summary: `Test.Data.Tables:TestContracts` pins `ApprovalRequest` `DRYRUNKEYS` at its full value (`...,example,notice,recipients,simulated`), and its message names Story 23.5's three keys. No product change. `Test.Fix.PartnerWarning` already pinned the full value; `Test.Fix.DryRun` and `Test.Watch.GoodMessages` read RepairResend's own `DRYRUNKEYS`, so none needed an edit.

Files changed: `src/ocutalon/cls/OcuTalon/Test/Data/Tables.cls`; this spec.

Review: 3 findings from four layers (three layers returned none). Patched 0, deferred 0, rejected 3 (3 low), each with its reason in the triage log. Follow-up review recommended: false (this follow-up pass patched no `high`).

Verification: `Test.Data.Tables` passed (5 methods) on slot D; `test-boundaries` and `test-class-rules` pass. mutation: `simulated` dropped from `ApprovalRequest` `DRYRUNKEYS` -> `Test.Data.Tables:TestContracts` red; restored byte-identical, class green again.

Residual risks: slot D's `OcuTalon.Data.Turn` was stale and was reloaded from the worktree; the CI re-run is the lead's.
