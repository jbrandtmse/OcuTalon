# Epic 7 Context: Approve the fix and the orders go through

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

This epic is the climax of the two-minute demo. For a data-format cause, OcuTalon proposes repair and resend with a dry run that changes nothing, raises one approval request fixed to exact targets (later failures get their own dry run and request in the same incident), and after approval re-checks each target, resends repaired copies, leaves the originals untouched and reports how many went through, for at least 500 messages, never retrying without a new approval and never leaving a run cut short by a restart unreported. Stories 7.1 to 7.6 are built and merged. The epic is re-opened for one post-1.0.0 story (first daily release, not rc1 scope): a date repair whose values read as valid dates both month first and day first must name the evidence for the source format, so a plausible conversion is never the only reason a user approves a resend. Until November 13 every date the demo partner sends is ambiguous this way.

## Stories

- Story 7.1: Repair and resend proposes a dry run that changes nothing (done)
- Story 7.2: The incident notice carries the dry run and one approval request (done)
- Story 7.6: Later failures in the same incident get their own dry run and approval request (done)
- Story 7.3: Approved repairs are re-checked and resent (done)
- Story 7.4: OcuTalon reports how many orders went through (done)
- Story 7.5: A resend cut short by a restart says how far it got (done)
- Story 7.7: A date repair that could read either way names its evidence (next, last; ledger item DW-644)

## Requirements & Constraints

- **The proposal rule (7.7).** When an incident's failed values could be read as MM/DD/YYYY or as DD/MM/YYYY, the diagnosis proposes `repair_resend` only if a reason names the evidence for the source format: a value with a day above 12, or the chosen reading matching each failed message's own date. Without that evidence the reply does not propose `repair_resend`.
- **The evidence rules from U-249's answer (the Planner, under the owner's delegation; the spec pins them at the plan gate):**
  - the date to match is the day each item arrived, with one day of tolerance either way;
  - when both readings match the arrival day, that is no evidence;
  - one test covers an instance whose local date differs from the UTC date.
- **The dry run (7.7).** It counts the values that read as valid dates both ways. When every value is ambiguous, it shows one extra line naming the evidence. The line is absent when any value has a day above 12. `{reading}` is "month first" or "day first", with a many-values form and a one-value form.
- **The wording is U-249's.** Its final answer superseded the draft in the runner's dispatch and keys on arrival (the line ends "Read {reading}, they match the day each {item} arrived."); take the exact text from that answer. Fitting it to the catalog's slot types is allowed. Any other wording change, and any change to a recorded eval case's expected outcome, is a `## Clarification Needed` (veto), never a silent re-baseline. This line is the only new user-facing text.
- **What must still pass.**
  - The demo incident still gets its repair, with month first matching each failed message's date as the evidence. `live:demo-path` and the online-demo specs stay green.
  - The lane-a evaluation cases (`Test/Eval/**`, including `orders-date-format`, `results-decimal-comma` and `shipments-epoch-time`) still pass.
- **Tests (7.7).** One case has only ambiguous dates and one has a day above 12; each checks the proposal rule and the dry-run line or its absence. Add a negative case: ambiguous dates with no matching evidence, where the reply must not propose `repair_resend`.
- **Epic-wide.**
  - Nothing changes during a dry run, and the CI mock receives no request during a dry run or an execution.
  - The model picks only the kind and its parameters (field, source format, target format), and code validates them. No model-written code runs.
  - Use the CI mock and its recorded replies only, never a real model key or a real Telegram bot.

## Technical Decisions

- **Where the rule lives.**
  - The prompt rule goes in `Agent/Diagnosis.cls`. Its static `INSTRUCTIONS` hold no template token.
  - Code may check the claimed evidence where parameters are already checked: `DiagnosisPayload.%OnValidateObject` -> `CheckFix` -> `Fix.Kind.Check` -> `RepairResend.CheckParameters(parameters, fields)`.
  - A reply that fails this check is `invalid` and takes Epic 5's fallback route. Only the bridge decides that a reply is unusable (AD-8).
  - `CheckFix` sees only the evidence pack's one sample body, read through `Bridge.ReplyCheck` (fail closed). The pack carries `firstAt`/`lastAt`, and `Watch.Reader` failures carry `at` in IRIS UTC as stored. The spec decides what an arrival-date check can rely on.
- **Reformatters.**
  - `Fix.Reformat` is pure: no database, no namespace, no SQL, and a value is never evaluated.
  - `ParseDate` (private) accepts only the format it is given. `Reads(value, format)` is the public test of a value.
  - Times convert only through `OcuTalon.Data.Time`.
- **Dry-run JSON.**
  - `RepairResend.DryRun` emits exactly the keys of `Bridge.Data.ApprovalRequest` `DRYRUNKEYS` (`affected,resend,leftOut,field,before,after,itemNoun`). `Test/Fix/DryRun` and `Test/Data/Tables` assert that exact list.
  - AD-16 allows "later fix kinds add their own keys in their step". An ambiguity count or evidence key therefore means changing DRYRUNKEYS (bridge, Lane A), both tests, and the notice and slot builders. The spec decides and records it.
  - `Watch/Notice.cls` maps dry-run keys to notice slots (`field`, `before`, `after`, `resendCount`).
- **Catalog.**
  - New keys go in `OcuTalon.Msg.Catalog.Watch`, rendered only by `OcuTalon.Msg.Catalog` through the same `*Out` path. Each key has `text` (and `web` where it differs), typed `slots` and a `source`.
  - The dry-run paragraph today lives inside `incident.withFix` and the later-request entry (and their one-copy forms): "Dry run: {count} {itemNoun} affected. Example: {field} {before} becomes {after}. ...".
- **Fixtures.**
  - The demo partner (`Demo/Orders/Partner.cls`, `PartnerTrigger` DATEFORMAT `MM/DD/YYYY`) writes today's instance-local date (`$ZDATE($HOROLOG,3)`) unless the batch gives one.
  - The 7.1 fixture and the `orders-date-format` eval snapshot use `10/16/2026`. Day 16 is above 12, so the line must be absent there.
  - The mock's `diagnosis` and `diagnosis-late` replies propose `repair_resend` MM/DD/YYYY -> YYYY-MM-DD, with reasons that name no date-order evidence.
- **Tests.**
  - `%UnitTest` classes go under `OcuTalon.Test.<Area>` and run on throwaways.
  - The mock's request log is the evidence for "no model request", and a test fails when that log is missing.
  - For failed orders, call `Partner.Send(count, dateFormat, traceRef, orderDate)` in OCUORDERS.

## UX & Interaction Patterns

- **Dry run block.** It gives the count, one before-and-after example naming the field, and what will be resent, ending "Nothing has changed yet." 7.7's line belongs to this block.
- **Voice.** Numbers first, and plain words ("becomes", never arrows). New public wording is a veto-window item.
- **EXPERIENCE.md.** If the line needs a row there, append one row to the dry-run section, away from Epic 33's and Epic 40's blocks.

## Cross-Story Dependencies

- **7.7 builds on 7.1 and 7.2:**
  - the fix-kind contract and parameter check (`Fix.Kind`, `RepairResend.CheckParameters`);
  - the diagnosis validation (`DiagnosisPayload.CheckFix`);
  - the dry run and its `DRYRUNKEYS` JSON;
  - the notice slot builder.

  7.3 to 7.5 (execution, results, Sweep and Reconcile) are untouched.
- **7.7's footprint:**
  - `Agent/Diagnosis.cls`, `Fix/Reformat.cls`, `Fix/Kind/RepairResend.cls`;
  - their tests under `Test/Agent/**` and `Test/Fix/**`;
  - new eval cases under `Test/Eval/**` if needed;
  - its bookkeeping.

  Anything else (DiagnosisPayload, Notice, DRYRUNKEYS, mock scenarios) is a footprint extension to report.
- **Contended now (fetch and compare heads first; never write in another worktree):**
  - `Msg/Catalog/Watch.cls` and `Test/Msg/Catalog.cls`: Epic 33 adds `digest.*` keys, and Epics 31 and 40 touch the catalog test. Add 7.7's key as one self-contained block at the end of the existing dry-run keys, never on lines another branch edits.
  - `Demo/**` and the e2e specs are read-only; a needed change there is a `## Clarification Needed`.
- **Never edit:**
  - the install path (`Install/**`, `src/module.xml`, `src/cpf/**`, `docker/**`, `install.sh`), which is under the Planner's stability watch until the tag;
  - any Lane B class or test (U-177), including the web page's files.
- **Release.** The rc1 push hold applies: commit locally and push nothing until the orchestrator says rc1 is cut. rc1 work takes precedence (yield on request).
- **Open ledger items:**
  - DW-644 is 7.7's.
  - DW-365 (a later request reuses the first `fixSummary`) stays `decision-pending` with the owner; don't change it ad hoc.
  - DW-318: a dry run reads only each group's newest 1000 failure keys.
