# Epic 23 Context: Deeper IRIS watch (step 5)

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Make OcuTalon watch IRIS more deeply and act on incidents more usefully: approved fixes beyond repair and resend (suspend, resume, reroute), partner delay notices sent only after approval, a written summary when an incident closes, and (Could) background checks that report between digests. Stories 23.2, 23.5, 23.6 and 23.7 are done. This compile serves the next two, in order: 23.10, judge-visible polish from the Contest Planner's hands-on pass of release 1.0.7 on the live demo (right partner on the demo notice, a notice that matches a resolved incident, the summary's "Fix:" full stop, the rail after Reject); then 23.9, which gives a suspend OcuTalon made a governed way back after its incident has closed, so an item is never left disabled with no path to resume it. Stories 23.3, 23.4 and 23.8 wait on Epic 36 and are out of scope.

## Stories

- Story 23.2: Suspend, resume and reroute with a dry run (done)
- Story 23.3: Setting-change cause and rollback (waits on Story 36.1)
- Story 23.4: Paging and escalation (waits on Story 36.2)
- Story 23.5: Partner delay notices sent only after approval (done)
- Story 23.6: Incident summary when an incident closes (done)
- Story 23.7: Watch queue backlogs between digests (done)
- Story 23.8: Saved SQL query watch (waits on Story 36.2)
- Story 23.10: Partner notice and summary polish from the 1.0.7 demo pass (next)
- Story 23.9: Resume a suspended item after its incident closes (after 23.10)

## Requirements & Constraints

**Partner notice and summary polish (23.10)**. All four items are ruled; wording below is public or model-facing text and must be used exactly.
1. **Wrong partner on the demo.** The guide's incident is the Orders feed, but the demo's one partner contact is named for Results, so the model wrote "Orders from Results Partner IT are delayed…". Rename the demo contact to `"Orders Partner IT" <it@orders-partner.example>`. The fixture already keys it to the Orders production. Update every test that pins the old name or address, and any README or EXPERIENCE line that names the recipient. Today neither names it: README's "Partner delay notices" bullet and EXPERIENCE's "Warn the partner" guide item say only "simulated contacts". Report the final README and EXPERIENCE lines in the PART READY report.
   - **Do not rename** the other "Results Partner IT <it@results-partner.example>". That is the *sample incoming email* about a certificate change (`Channel.SimMailbox.In` `PARTNERFROM`/`PARTNERBODY`, the mailbox's `fromPrefill`, `eval/mail-partner-notice`, the EXPERIENCE sample-email table). It is a different fixture and correctly belongs to the Results partner.
2. **Notice on a resolved incident.** The notice said "We are looking into a fix and will share updates." after the fix had already run. Two changes:
   - the draft's facts gain the incident's state;
   - the draft instruction gains this sentence, verbatim: "If the incident is resolved, say that the affected orders went through after the fix, and don't say that work is still going on or that updates will follow."
   Add an eval or CI mock case that shows a resolved incident's draft without "looking into" or "will share updates". This is model-facing, so it goes on the Planner's next RC-eval checklist.
3. **Summary "Fix:" line.** It lacks its final full stop ("…after you approve"). Add the full stop and update the pin that holds the old text.
4. **Rail after Reject (LOW).** After Reject, the status rail's Approval requests briefly still listed the rejected request. Fix it in 23.10 if the cause is a one-line refresh; otherwise file the gap in the ledger with its cause.

**Resume after close (23.9)**
- It applies to an item that OcuTalon suspended through an executed `suspend_item` request of an incident the user can see, after that incident has closed.
- The spec must choose between two options, and the Contest Planner leans to (b):
  - (a) a resume raised on the closed incident, which never moves the incident's state;
  - (b) an incident with an active suspend stays open until a resume or Dismiss.
- Either way:
  - exactly one approval request with its own dry run is raised;
  - the item is re-checked before the resume runs;
  - nothing changes until approval;
  - a second session, or a user outside the incident's ownership scope, cannot resume it.
- Background (DW-1068): `propose_fix` resolves only `open` and `resolved` incidents (`WatchTools` `FIXABLE`; partner warnings use `WARNABLE`), so after close it answers `no_incident`. `Fix.Run.Suspended` ignores incident state.
- The ruled `result.itemSuspended` text limits the undo to "while this incident is open" and points to the Management Portal after the incident closes. Any change to that text, the README sentence or the `Agent/Chat.cls` resume line is public text and needs a ruled wording.
- On the online demo, suspend and resume are refused for every item (`ONLINESHARED`) because every visitor shares the Orders production. Only reroute is offered there.

**Rules for every story**
- No risky action runs without an approved request, and resume is risky.
- A rejected or expired request changes nothing, and the user is told.
- Requests expire after 24 hours. The first answer from any channel wins.

## Technical Decisions

**Partner-warning design (Story 23.5).** `partner_warning` is a fix kind (`Fix.Kind.PartnerWarning`) with these traits:
- It is asked for in the chat only and never named by a diagnosis: `ASKED` 1, `DIAGNOSED` 0.
- Its text is model-drafted (`DRAFTED` 1), it needs no IRIS resources, and its targets are contact ids (`TARGETTYPE` contact).
- It never moves the incident's state (`MOVES` 0). Raising, approving, rejecting or expiring the request changes no state and is not a fact of the transition table.
- It is answered in every state but `closed`.

Code pointers:
- **Contacts:** `Fix.PartnerContacts`, a read-only fixture in code (XData `Contacts`, a JSON array of `{id, production, name, address}`).
  - It has no table, no global and no setting, and it works in demo mode only: `For` returns `[]` with demo mode off, so an own install drafts nothing.
  - The one contact is id 1, keyed to `OcuTalon.Demo.Orders.Production`. Addresses must stay example-domain and fictional.
- **Drafting:**
  - `IncidentManager.AskedDraft` checks for refusals first: `NOITEM`, `NOCONTACTS`, `ALLOWANCE`, and `already_asked` (a request of the kind already waiting).
  - `StartDraft` then self-sends an async `Watch.Msg.Draft`, and a `Decide` turn runs with completion key `DRAFTKEY`. The turn is untrusted, fresh and owned by the asking session. Its input is `PartnerWarning.Facts(incident)` and its instruction is the kind's `SystemNote`.
  - `Drafted` normalises the reply to one line (at most `NOTICEMAX`), gets the dry run and raises one request.
  - A failure tells the user `result.partnerNotDrafted`.
- **Facts:** partner names, production, failed items, count with noun, first and last failure, and the plain cause. Never a message body, sample error, setting value or evidence. 23.10 adds the state line here; 23.10's instruction sentence goes into `SystemNote`.
- **Dry run:** keys `notice`, `recipients: [{name, address}]` and `simulated: 1`. `Recheck`/`Execute` re-read each target against the fixture and skip a contact that changed. `Ready` is 0 with `NOTSETUP` when demo mode is off, so an approved notice is kept as an approved draft with a plain line and never dropped silently.
- **Delivery:** `Fix.Executor.Deliver` sends one `Fix.Msg.PartnerNotice` per recipient session to `SimMailboxOut`, with the row's approved text byte for byte. It never goes through `EmailOut`; real email is a parked Epic 21 follow-up. No public text may say or imply that a real email was sent.
- **Tests and mocks:** `Test.Fix.PartnerWarning`, `Test.Fix.PartnerDraft` (the IncidentManager probe; draft request and Facts exclusion) and `Test.Fix.PartnerTurns`, among others. Mock scenarios are `ci/mock/scenarios/B/partner-notice-draft.json` and `partner-warning-ask.json`, and `A/partner-warning*.json`. Web: `web/scripts/approval-view.test.mjs`, `web/e2e/cards/approval-card.spec.ts`. Grep `results-partner` to find every pin, then leave out the sample-email ones listed above.

**Incident summary (Story 23.6).**
- On every move into `closed`, `IncidentManager` composes the summary in code (`Watch.Summary`) with no model call. It stores the summary on the row in the same save and sends one `summary` notification.
- Lines are `Msg.Catalog.Watch` keys `summary.*`, among them `title`, the timeline keys (`requested*`, `approved(By)`, `rejected(By)`, `expired`, `fixStarted/Ended/Interrupted`, `closed*`), `cause`, `element`, `noCause`, `evidence`, `sampleError`, `fix`, `noFixRan`, `groups`, `messages`, `cost`/`costUnknown`, `item*`, and `partnerSent/Kept/NotSent`.
- `summary.fix` is `"Fix: {fix}"`, with a `sentence` slot filled from `incident.FixSummary`. The catalog skips a following period only when the value ends in "?", "!" or "…", so check how a fix summary that already ends in "." renders.
- Pins live in `Test.Msg.Catalog` (the `summary.fix` fixture) and `Test.Watch.Summary`.
- A partner-notice run is not a fix: it adds no `summary.fix` line and does not remove `noFixRan`.

**Status rail approvals.**
- `web/src/app/rail/rail-view.ts` `railView` lists the store's *pending* approvals. The store keeps every request, and the view filters it.
- `live-store.ts` applies each `approval` live event by `ref`.
- `approvals/answer-press.ts` handles the web press.
- When looking for the cause of the lag after Reject, start from where the rejected state reaches the store: the live event or the answer response.

**Incidents and fixes (AD-15, AD-16) for 23.9.**
- `IncidentManager` is the only writer of `Incident` and `FailureGroup` rows and the only publisher of `incident` events. Others reach it through `IncidentCommand`, `ApprovalOutcome`, `FixResult` or `ProposeFix`.
- Every state move goes through one transition table (`Watch.Transitions`). Its unit test covers every row and every refused move. Today "anything on a closed incident" is refused, and `resolved` goes to `closed` on `closeQuiet`, `dismiss` or `closeForReplay`.
  - Option (b) changes the close rows: `Checks`' 15-minute `closeQuiet` and replay for an incident with an active suspend.
  - Option (a) is a closed-incident request, using the `MOVES` 0 precedent of the partner warning.
  - Either is a ruled change to the table, its test and the spine's AD-15 text, in the same change.
- A chat-asked fix arrives as `ProposeFix`. `IncidentManager` runs one synchronous dry run, then `Approval.Raise`.
- Fix kinds sit under `Fix.Kind` with `DryRun`, `Recheck`, `Execute`, a parameter schema and `RESOURCES`. The item kinds need `%Ens_ConfigItemRun:U`, and their dry-run keys are `item`, `before` and `after`.
- `FixExecutor` runs only from an approved, unexpired row that is not already executing (set atomically). It re-checks each target and skips and reports one that changed. It switches namespace only in its one method and calls `Ens.Director.EnableConfigItem`.
- Every action is audited through `Bridge.Audit`. Undoing a suspend raises exactly one `resume_item` request (the `already_asked` rule).
- A suspend OcuTalon made is attributed to its fix and never reported as a new state change: `Checks.Process.Findings` uses `Fix.Run.Suspended(namespace, production, since, .fresh)`.
- Item result keys come from `Watch.Notice.ResultKey`. The summary's item lines are `summary.itemSuspended/Resumed/NotChanged`.

**Background checks (AD-18), as Story 23.7 left them.**
- A queue-backlog row (`Kind` `queues`, one per session) is created and removed by `WatchOps`. On each `Tick`, `Checks` reads it through `Watch.Reader` only, applies `Checks.Queues.Over` against `checks.thresholds.*`, and sends one `watch.queueBacklog` finding per crossing (at most once an hour per queue). An unreadable namespace makes the run `not_checked`.
- A new item, table, row type or event type goes into the spine's ownership tables in the same change.

## UX & Interaction Patterns

- **Partner request card:** an extra approval request in the incident card. It shows the exact text and every recipient; on the demo the recipients are simulated contacts and the notice goes to the Simulated mailbox. Its rail title is the partner-warning title from `rail-view.ts` `approvalTitle`. The guide's "Warn the partner" item needs an incident that isn't closed.
- **Answered states:** "Approved from {channel} at {time}" and "Rejected from {channel} at {time}. Nothing was changed." The first answer wins. Within 5 seconds every copy (the chat card, the rail row, the phone, Telegram) shows the answer or leaves its list, which is the bar 23.10 item 4 measures against. An empty rail section reads "None waiting."
- **Summary:** it arrives in the chat, on the Simulated phone and in the paired chat. "Show me the incident summary" gets it again, and the guide's "Read the incident summary" item closes the resolved incident.
- **Closed incident card:** compacted to its headline and each request's result. Under option (a), a resume raised on a closed incident must fit this compact card. Under option (b), the incident stays open and shows Dismiss.
- **Suspend, resume and reroute:** each uses the approval request card with its own dry run (item state before and after), ending "Nothing has changed yet." while pending. Each approved request gets a result band, followed by "Recorded in the IRIS audit log."

## Cross-Story Dependencies

- 23.10 runs first (ruling: straight after 23.7, before 23.9) in this worktree. It touches 23.5's fixture, draft and tests, 23.6's `summary.fix` catalog entry and pins, and the web rail.
- 23.9 builds on:
  - 23.2's kinds, `propose_fix`, `Fix.Run.Suspended`, the attribution in `Checks.Process.Findings` and the ruled `result.itemSuspended` text;
  - 23.6's summary, composed on every move into `closed` (option (b) delays that move);
  - 23.7's `Checks` tick, which also sends `closeQuiet`.
- The (a)/(b) choice goes to the Contest Planner at the spec stage.
- 23.3 waits on Story 36.1. 23.4 and 23.8 wait on Story 36.2. 24.2's partner-contact table will later replace the 23.5 fixture.
