# Epic 7 Context: Approve the fix and the orders go through

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

This epic is the climax of the two-minute demo. For a data-format cause, OcuTalon proposes repair and resend with a dry run that changes nothing, raises one approval request fixed to exact targets (later failures get their own dry run and request in the same incident), and after approval re-checks each target, resends repaired copies, leaves the originals untouched and reports how many went through, for at least 500 messages, never retrying without a new approval. Stories 7.1 to 7.8 are built. The epic is re-opened for one story, 7.9: before any fix is offered, the dry run also applies the repair in memory to recent good messages from the same source and shows that it would leave them unchanged. If the repair would change any good message, no fix is offered. The user then knows the fix touches only the broken messages. The target is the Saturday release (Sunday 19Z at the latest).

## Stories

- Story 7.1: Repair and resend proposes a dry run that changes nothing (done)
- Story 7.2: The incident notice carries the dry run and one approval request (done)
- Story 7.6: Later failures in the same incident get their own dry run and approval request (done)
- Story 7.3: Approved repairs are re-checked and resent (done)
- Story 7.4: OcuTalon reports how many orders went through (done)
- Story 7.5: A resend cut short by a restart says how far it got (done)
- Story 7.7: A date repair that could read either way names its evidence (done)
- Story 7.8: The web incident card shows the either-way date line too (done)
- Story 7.9: The dry run shows the fix leaves good messages unchanged (next, last; backlog)

## Requirements & Constraints

- **The check (7.9).** For a validated repair and resend whose dry run has targets, apply the registered reformatter, in memory only, to the same field of the last N=20 successfully processed messages from the same source as the failed ones. Record the count checked and the count the repair would change.
- **Read only.** The check resends nothing and writes nothing to any message, header, body, setting or queue in either namespace. It calls no model: the CI mock receives no request during it.
- **Nothing changed: one more notice line.** The with-fix notice's "Dry run:" paragraph gets one more line with the count checked and the count changed. The Planner rules the exact text at the spec gate. Never invent public wording; any wording question goes to the spec gate.
- **Any change: no fix.** If any good message would change, no fix is offered and no request is raised. The incident gets the no-fix notice, following 7.7's no-evidence pattern (U-251). The Planner rules any no-fix wording at the spec gate.
- **Approval runs exactly the dry run.** An approved request runs the same kind, parameters and fixed targets the dry run showed, and nothing else.
- **Required tests.**
  - A demonstrated mutation: a fix that changes one good message must withhold the offer.
  - The case with no good messages.
  - A case with fewer than 20 good messages.
  - A check that the approved change equals the dry run's.
- **Epic-wide.**
  - Use only the CI mock and its recorded replies, never a real model key or a real Telegram bot.
  - `live:demo-path` and the online-demo specs stay green, and no recorded eval expectation changes.

## Technical Decisions

- **Fix kinds (fixed set).**
  - A kind implements `DryRun`, `Recheck` and `Execute` against fixed targets, with a parameter schema.
  - The model picks only the kind and its parameters (field, source and target format). Code validates them, and no model-written code runs.
  - `FixExecutor` loads the kind, targets and change from the `ApprovalRequest` row alone: `FixKind`, `FixParameters` and `FixTargets`.
- **The stored dry run.**
  - It is JSON on the row with exactly `DRYRUNKEYS` (`affected`, `resend`, `leftOut`, `field`, `before`, `after`, `itemNoun`), pinned by `Test/Fix/DryRun` and `Test/Data/Tables`.
  - The architecture lets later fix kinds add their own keys. Whether 7.9's counts become stored keys (a bridge change plus both pinning tests) or are carried another way is the spec's decision, and the spec records it.
- **Reading messages.**
  - `OcuTalon.Watch.Reader` is the one class that switches namespace to read a production. Fix may call it.
  - Today it reads only failed headers (Status Error) and their evidence. It has no read of successfully processed messages, so the good-message read belongs in the Reader, not in Fix.
- **The reformatter.** `OcuTalon.Fix.Reformat.Convert` refuses a value that doesn't read in the source format. The spec must say how a good value that the source format refuses counts in "checked" and "changed".
- **The refusal path (7.7).**
  - A refused `RepairResend.DryRun` returns an error with a plain reason (as `NOEVIDENCE` does).
  - `IncidentManager` then sends `incident.noFix` with the cause, raises no request, leaves the incident open with variant `no_fix`, and logs one Type 3 warning that names the reason.
  - `Test/Fix/EitherWay` and `Test/Fix/Raise` show the pattern.
- **Notice keys.**
  - `Watch/Notice` picks the with-fix key: `incident.withFix` or `incident.withFixEitherWay`, and for later requests `incident.laterRequest` or `incident.laterRequestEitherWay`. It builds slots in `WithFixSlots`.
  - The new line has to sit beside the either-way line without doubling the variant keys by hand. The spec decides how, and any catalog addition is one self-contained block.
  - Producers never render text: `OcuTalon.Msg.Catalog.Render` does that in the `*Out` operations.
- **Tests.**
  - `%UnitTest` classes go under `OcuTalon.Test.<Area>`.
  - Integration tests run on throwaways and in CI only, through `Test.Watch.Case`.
  - The mock's request log is the evidence for "no model request".

## UX & Interaction Patterns

- **Dry run block and paragraph.**
  - It gives the count, one before-and-after example naming the field, and what will be resent.
  - It ends "Nothing has changed yet." while the request is pending.
  - The voice puts numbers first, uses plain words ("becomes", never arrows) and has no exclamation marks.
- **No-fix notice.** It shows the cause and the failure groups, with no approval request and no buttons. The demo guide already has a hint for a notice without a fix (P25).
- **Scope of the card.** 7.9's criteria name only the notice's paragraph, not the web incident card. Any card change is out of scope unless the spec gate rules otherwise.
- **Short screens.** At 1280x600 the incident card's headline, cause, dry-run count, Approve and Reject stay visible without scrolling.

## Cross-Story Dependencies

- **What 7.9 builds on.**
  - 7.1: `RepairResend.DryRun` and the registered reformatters.
  - 7.2 and 7.6: the with-fix and later-request notices, and `Raise`.
  - 7.3: `Recheck` and `Execute` read the row only.
  - 7.7: the refusal path to `incident.noFix`, and the either-way line.
  - Keep 7.7's evidence rule and 7.8's card row behaving exactly as they do now.
- **Later requests.** Each request has its own dry run, so the check should apply to a later round's dry run the same way.
- **Open ledger items.**
  - DW-318: a dry run reads only each group's newest 1000 failure keys.
  - DW-655 and DW-653 are burn-down items. Don't fix them in passing.
- **Release.** Nothing goes to `main` or `release/*`. The exact public texts come from the Planner at the spec gate.
