# Epic 23 Context: Deeper IRIS watch (step 5)

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Incidents get more governed fixes: suspend, resume and reroute, plus setting rollback later. Failures are linked to recent setting changes. The on-call person is paged, with escalation to a backup. Partner delay notices are drafted and sent only after approval. Every incident closes with a summary written by code. Queue backlog and saved SQL query watches report between digests (Could). Lane A owns the epic. It ships in the first daily release after it merges. The next story is 23.9, which makes sure an item OcuTalon suspended is never left disabled without a governed way back. It is in 1.0.8 if it is green on the feature branch by the cut, otherwise 1.0.9.

## Stories

- Story 23.2: Suspend, resume and reroute with a dry run (done)
- Story 23.3: Name the setting change behind an incident and offer its rollback (waits on Story 36.1)
- Story 23.4: Decide when to page the on-call person and when to escalate to the backup (waits on Story 36.2)
- Story 23.5: Draft partner delay notices that are sent only after approval (done)
- Story 23.6: Write an incident summary when an incident closes (done)
- Story 23.7: Watch queue backlogs between digests (done)
- Story 23.8: Watch a saved SQL query as a read-only SQL user (waits on Story 36.2)
- Story 23.9: Resume a suspended item after its incident closes (next; option (b), ruled 2026-11-12)
- Story 23.10: Partner notice and summary polish from the 1.0.7 demo pass (done)
- Story 23.11: Say in a partner notice only how the incident ended (done)

## Requirements & Constraints

- **Incident hold for a suspend (ruled 2026-11-12, option (b)):**
  - An incident that holds an active suspend is not closed by the 15-quiet-minutes close or by the replay close.
  - It closes only by Dismiss, or by the quiet close once a resume has ended the hold.
  - Dismiss always closes it.
  - After a held incident is dismissed, `Checks` reports the still-disabled item once, at the suspend's time.
  - Accepted limit: if the item is enabled by hand in the Management Portal, the incident stays held until Dismiss.
- **Break the feed (demo mode):** it normally closes a resolved Orders incident first. It does not close one that still holds a suspend; it shows its hint instead.
- **Resuming after close:** exactly one approval request with its own dry run is raised. The item is re-checked before the resume runs. A second session, or a user outside the incident's ownership scope, cannot resume it.
- Every fix has a dry run that changes nothing, and it runs only after approval. Each undo (resume after a suspend, restoring a rolled-back value) is one approved action.
- A copy or a suspend that OcuTalon made is attributed to its fix. It is never reported as a new failure or a new state change.
- Partner notices go only to configured contacts, using the exact approved text. On the demo they go to the Simulated mailbox, and no text may imply that a real email was sent. A notice states only the outcome that OcuTalon's own records support.
- Summaries are composed by code with no model request. The summary's cost is the sum of the incident's usage rows. Summaries are purged with their incidents.
- The online demo is unchanged: suspend and resume stay refused there, and only reroute is offered.

## Technical Decisions

- **Incident ownership:** `IncidentManager` is the only writer of `Incident` and `FailureGroup` and the only publisher of `incident` events. Other parts ask it through `IncidentCommand` (`dismiss`, `closeQuiet`, `closeForReplay`), `ApprovalOutcome` or `FixResult`. Its unit test covers every transition-table row and every refused move.
- **Transition table (2026-11-12 change):**
  - `resolved` → `closed` on `dismiss`, or on `closeQuiet` / `closeForReplay` only while the incident holds no suspend.
  - `open` (noticed) → `closed` on `dismiss`, or on `closeQuiet` only with demo mode off and no suspend held.
- **Holds a suspend:** true while an item's newest item-kind run that changed it, in that production, is a `suspend_item` run of one of this incident's requests (`Fix.Run`).
- **On every move into `closed`:** `Watch.Summary` composes the summary, it is stored in the same save, and the `summary` notification is sent.
- **Fix kinds:**
  - Kinds live under `OcuTalon.Fix.Kind` and implement `DryRun`, `Recheck` and `Execute`, each with a parameter schema.
  - `Execute` carries only the `ApprovalRef`. `FixExecutor` trusts only the approved row: approved, not expired, not already executing (set atomically), and the service user holds the kind's `RESOURCES`.
  - `suspend_item`, `resume_item` and `reroute` are chat-asked only (not `DIAGNOSED`), via `ProposeFix` → synchronous dry run → `Approval.Raise`.
  - Their dry-run keys are `item`, `from`, `to` and `example`. Item kinds report one result per item.
  - Suspend and resume run `Ens.Director.EnableConfigItem` from `FixExecutor`'s single namespace-switching method.
- **Privileges:** a local install's service user holds `%Ens_ConfigItemRun:U`; the online-demo install does not. Rollback (Story 23.3) will declare `%Ens_ProductionConfig` WRITE.
- **`partner_warning` kind:** has `MOVES` 0, so it never changes incident state. It is drafted through a self-sent `Watch.Msg.Draft` and a `Decide` turn, and has a `Ready` hook (with no delivery set up, the notice is kept as an approved draft).
- Audit goes only through `OcuTalon.Bridge.Audit`. Text goes through `OcuTalon.Msg.Catalog` keys (AD-32). Tests go in `OcuTalon.Test.Fix`, `.Watch` and `.Checks`, with CI mock scenarios under `ci/mock/scenarios/A/`. New tool names are added to `OcuTalon.Tools.Names`.

## UX & Interaction Patterns

- Each fix uses the approval request card with its own dry run and result band. The `incident` payload's `Requests` carries `FixKind`, `Item` and `Count`.
- A closed incident card is compacted to its headline and each request's result. While a suspended item is still suspended, it closes only by Dismiss (or after a resume).
- The demo guide describes suspend and resume only as working "on your own install".

## Cross-Story Dependencies

- Story 23.9 builds on 23.2's suspend and resume kinds and its `result.itemSuspended` text, which today limits the undo to an open incident. It also builds on 23.6's closing summary and on the heartbeat/`Checks` `closeQuiet` path.
- Story 23.3 waits on Story 36.1 (setting history and spine names). Stories 23.4 and 23.8 wait on Story 36.2 (on-call keys, the acknowledgement verb, the save-SQL-query-watch verb). Stories 23.4 and 23.6 use the Watch area's `Purge(daysToKeep)` (Story 30.2).
- Real email for partner notices through `EmailOut` is parked as a 23.5 follow-up under Epic 21.
