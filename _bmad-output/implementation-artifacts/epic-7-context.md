# Epic 7 Context: Approve the fix and the orders go through

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

This epic is the climax of the two-minute demo. For a data-format cause, OcuTalon proposes repair and resend with a dry run that changes nothing, raises one approval request fixed to exact targets (later failures get their own dry run and request in the same incident), and after approval re-checks each target, resends repaired copies, leaves the originals untouched and reports how many went through, for at least 500 messages, never retrying without a new approval and never leaving a run cut short by a restart unreported. Stories 7.1 to 7.7 are built. One post-1.0.0 story remains: 7.7 made a date repair whose values read as valid dates both month first and day first name its evidence in the notice, and people on the demo path approve on the web incident card, so the same line must show there. A plausible conversion is never the only reason to approve a resend. Until November 13 every date the demo partner sends is ambiguous this way.

## Stories

- Story 7.1: Repair and resend proposes a dry run that changes nothing (done)
- Story 7.2: The incident notice carries the dry run and one approval request (done)
- Story 7.6: Later failures in the same incident get their own dry run and approval request (done)
- Story 7.3: Approved repairs are re-checked and resent (done)
- Story 7.4: OcuTalon reports how many orders went through (done)
- Story 7.5: A resend cut short by a restart says how far it got (done)
- Story 7.7: A date repair that could read either way names its evidence (done; first CI pending)
- Story 7.8: The web incident card shows the either-way date line too (next, last; ledger item DW-645)

## Requirements & Constraints

- **The payload (7.8).** For an approval whose date repair found every value valid both ways, the approval payload carries the ambiguity flag and the reading (month first or day first) with the dry run's other fields.
- **The card row (7.8).** The dry-run block shows one row with U-249's catalog line, word for word as the notice shows it. The row is absent whenever the notice's line is absent: any day above 12, same-date values only (11/11, 12/12), or no either-way case.
- **The line (U-249).**
  - Many values: "All {count} dates are valid whether read month first or day first. Read {reading}, they match the day each {item} arrived."
  - One value: "The date is valid whether read month first or day first. Read {reading}, it matches the day the {item} arrived."
  - `{count}` is the resend count. `{item}` is the one form of the item noun ("order" in the demo, "message" when unknown).
- **No new public text.** Any new label comes back as a veto item, never a silent choice. Any other wording change is a `## Clarification Needed`.
- **Tests (7.8).** A payload test and a web test pin the row's presence for the either-way case and its absence for a day above 12.
- **Epic-wide.**
  - Nothing changes during a dry run, and the CI mock receives no request during a dry run or an execution.
  - The model picks only the kind and its parameters, and code validates them. No model-written code runs.
  - Use the CI mock and its recorded replies only, never a real model key or a real Telegram bot.
  - `live:demo-path` and the online-demo specs stay green; no recorded eval expectation changes.

## Technical Decisions

- **What 7.7 settled (do not reopen).**
  - `RepairResend.Evidence` gives `oneway`, `arrival`, `same`, `none` or `n/a`. The dry run refuses on `none`, so every raised request with differing readings has its evidence. Arrival means the UTC date of the failed header, one day of tolerance either way.
  - A value whose two readings are the same date is not ambiguous: no line, no evidence needed (U-250). A mixed set shows the line as worded.
  - A data-format reply with no fix gets `incident.noFix` with its cause, nothing approvable (U-251).
- **The either-way test is derived, not stored.**
  - The stored dry run keeps exactly the `DRYRUNKEYS` list, which `Test/Fix/DryRun` and `Test/Data/Tables` pin. No flag is on the row.
  - The notice decides in `Watch/Notice.cls`: the private `Reading(dryRun, parameters)` needs the request's source format to be an order format and the dry run's `before` to read both ways as two different dates. The example rule in the dry run makes that true exactly when every target value reads both ways.
  - The source format is in the row's `FixParameters`, which the payload does not expose. `Live/Payload` references neither `Watch.Notice` nor `Fix` today.
  - The notice and the row must agree by one rule, not two copies. The spec decides how the payload gets it and records it. A stored key would mean a bridge change and both pinning tests.
- **Payload.**
  - `Live.Payload.Approval.FromRow` is the one builder for live events, REST and the rail. It maps the dry run key by key into `Part.DryRun`, whose doc says its keys are DRYRUNKEYS.
  - `web/src/app/live/payloads.ts` is generated from the payload classes (`npm --prefix web run payloads`). Never hand-edit it.
- **The page catalog cannot render the line yet.**
  - The line has no key of its own: it sits inside `incident.withFixEitherWay` and `incident.laterRequestEitherWay` (and their one forms). The two keys copy their parents' text (DW-655).
  - `web/scripts/catalog.mjs` keeps an allowlist with no `incident.*` key. It refuses a listed key with both a web form and a one form (both variants have both), and it allows a text slot only for the keys of `TEXT_SLOT_KEYS` (`reading` and `item` are text slots).
  - The notice's text is rendered by the server; the page's `msg/catalog.ts` is generated. A hand copy of the line in `APPROVAL_TEXTS` is how the card and the notice would drift. The spec decides how the page gets the words, and a test holds them equal to the catalog's.
- **The card.**
  - `approval-view.ts` builds `DryRunView` as text and the component only interpolates it. It stays framework-free and runs under Node in `web/scripts/approval-view.test.mjs`.
  - The block's labelled rows are Before, After and Will resend; `dry-note` is the existing row with no label.
  - A later request is its own approval payload, so the rule covers later rounds with no special case.
- **Tests.** `%UnitTest` classes go under `OcuTalon.Test.<Area>` and run on throwaways. The mock's request log is the evidence for "no model request".

## UX & Interaction Patterns

- **Dry run block.** It gives the count, one before-and-after example naming the field, and what will be resent, ending "Nothing has changed yet." while pending. After the answer the block stays as a record; the spec decides whether the row stays with it (the notice's line does not depend on the state).
- **Short screens.** At 1280x600 the incident card's headline, cause, dry-run count, Approve and Reject must stay visible without scrolling the chat. The demo path has this row every day until November 13, so the extra line must not push them off.
- **Voice.** Numbers first, plain words ("becomes", never arrows).
- **EXPERIENCE.md.** It has no row for the line today. If it needs one, append it to the dry-run section, away from Epic 33's and Epic 40's blocks.

## Cross-Story Dependencies

- **7.8 builds on 7.7** (the line, the two variant keys, `Notice.Reading`, the evidence rule) and on Epic 6's approval card. 7.1 to 7.6 are untouched. 7.7 never waits for 7.8.
- **7.8's footprint.** Epic 31 has merged, so the wait is over. U-252 allows exactly these Lane B files in this Lane A epic: the `Live/Payload` approval payload and `web/src/app/approvals/approval-view.ts`. Anything else it needs (the card component, `catalog.mjs`, generated modules, `Notice.cls`, tests) is a footprint extension to report.
- **Contended now (fetch and compare heads first; never write in another worktree):**
  - `Test/Live/Payloads.cls`, `Live/Publish.cls` and `payloads.ts`: Story 39.7 (re-homed to Lane B) edits them. 7.8 may append in `Test/Live/Payloads.cls`, and the second to merge makes the plain union, then regenerates `payloads.ts`.
  - `Msg/Catalog/Watch.cls`: Epic 33 adds `digest.*` keys. `Test/Msg/Catalog.cls`: Epics 33 and 40. Any catalog addition is one self-contained block at the end of the dry-run keys, never on lines another branch edits, and no existing key's text changes.
  - No open branch touches `web/src/app/approvals/**`.
- **Never edit:** the install path (`Install/**`, `src/module.xml`, `src/cpf/**`, `docker/**`, `install.sh`), under the Planner's stability watch until the tag; any other Lane B class or test. `Demo/**` and `eval/**` stay read-only.
- **Release.** The rc freeze and push holds on this lane ended at the rc4 cut; nothing goes to `main` or `release/*`. Epic 7's merge waits for the 1.0.0 tag and for U-253: the Planner's five real-model trials on a pushed green head, where 5 of 5 merges and less holds. 7.8 ships in the same daily release as 7.7 if it makes the cut.
- **Open ledger items:**
  - DW-645 is 7.8's.
  - DW-655 (the variant keys copy their parents) and DW-653 (`Eval.Record` refuses a fix-less data-format expectation) are burn-down items; don't fix them in passing.
  - DW-318: a dry run reads only each group's newest 1000 failure keys.
