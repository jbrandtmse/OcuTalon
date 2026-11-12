# Epic 23 Context: Deeper IRIS watch (step 5)

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Make OcuTalon watch IRIS more deeply and act on incidents more usefully. That means approved fixes beyond repair and resend (suspend, resume, reroute), partner delay notices sent only after approval, a written summary when an incident closes, and (Could) background checks that report between digests. Stories 23.2, 23.5, 23.6, 23.7 and 23.10 are done. This compile serves the next two, in order:
- **23.11** makes a partner notice say only how the incident actually ended. OcuTalon's code builds the Outcome fact from its own records, so the notice never claims the orders went through when some failed again, were skipped, or the flow was suspended or rerouted.
- **23.9** gives a suspend OcuTalon made a governed way back after its incident has closed.

Stories 23.3, 23.4 and 23.8 wait on Epic 36 and are out of scope.

## Stories

- Story 23.2: Suspend, resume and reroute with a dry run (done)
- Story 23.3: Setting-change cause and rollback (waits on Story 36.1)
- Story 23.4: Paging and escalation (waits on Story 36.2)
- Story 23.5: Partner delay notices sent only after approval (done)
- Story 23.6: Incident summary when an incident closes (done)
- Story 23.7: Watch queue backlogs between digests (done)
- Story 23.8: Saved SQL query watch (waits on Story 36.2)
- Story 23.10: Partner notice and summary polish from the 1.0.7 demo pass (done)
- Story 23.11: Say in a partner notice only how the incident ended (next)
- Story 23.9: Resume a suspended item after its incident closes (after 23.11)

## Requirements & Constraints

**Outcome fact (23.11, DW-1165).** The Contest Planner ruled these strings. They are model-facing public text, so use them exactly. OcuTalon's code builds them from the incident's records; the model never computes them.
- All affected messages resent, none failed again or skipped: "Outcome: all {N} affected orders went through after the fix."
- Some failed again or skipped: "Outcome: {A} of the {N} affected orders went through after the fix, and {R} did not."
- Ended by a reroute: "Outcome: the {N} affected orders were resent by another route."
- Ended by a suspend: "Outcome: the affected flow was paused, and the {N} affected orders haven't gone through yet."
- Any other ending, or unknown counts: no Outcome line.
- Replace 23.10's resolved-incident sentence in the draft instruction, verbatim, with: "If the incident is resolved, say how it ended using only the Outcome fact, and don't say that work is still going on or that updates will follow. If there is no Outcome fact, don't say whether the orders went through."
- The facts still carry no item or target names, setting values or message contents. A reroute's target stays out of the Outcome line.
- Tests:
  - one CI mock case per outcome; "went through" appears only in the all-through case, and no case contains "looking into" or "will share updates";
  - a unit test for each outcome builder, including zero counts and a resolved incident with no fix.
- If the records can't support a line exactly as written, the spec may adjust the wording. The changed wording goes to the Contest Planner as public text before commit.
- This is model-facing, so it goes on the Planner's next RC-eval checklist. CI proves only what the code sends to the model.

**Resume after close (23.9, DW-1068).**
- It applies to an item OcuTalon suspended through an executed `suspend_item` request of an incident the user can see, once that incident has closed.
- The spec chooses between two options, and the Planner leans to (b):
  - (a) a resume raised on the closed incident, which never moves the incident's state;
  - (b) an incident with an active suspend stays open until a resume or Dismiss.
- Either way:
  - exactly one approval request with its own dry run is raised;
  - the item is re-checked before the resume runs;
  - a second session, or a user outside the incident's ownership scope, cannot resume it.
- Today `propose_fix` resolves only `open` and `resolved` incidents (`FIXABLE`), so after close it answers `no_incident`. `Fix.Run.Suspended` ignores incident state.
- The ruled `result.itemSuspended` text limits the undo to "while this incident is open" and points to the Management Portal after close. Changing it, the README sentence or the `Agent/Chat.cls` resume line needs ruled wording.
- On the online demo, suspend and resume are refused for every item (`ONLINESHARED`). Only reroute is offered there.

**Rules for every story.**
- No risky action runs without an approved request.
- A rejected or expired request changes nothing, and the user is told.
- Requests expire after 24 hours, and the first answer from any channel wins.
- The approver sees the exact notice text and every recipient. A notice is never sent to an address an admin didn't configure.

## Technical Decisions

**Partner warning, as 23.5 and 23.10 left it.**
- `partner_warning` (`Fix.Kind.PartnerWarning`) is a chat-asked fix kind (`ASKED` 1, `DIAGNOSED` 0, `DRAFTED` 1) with targets of type contact. It never moves the incident (`MOVES` 0), and it is answered in every `WARNABLE` state: open, awaiting approval, fixing and resolved.
- `PartnerWarning.Facts(incident)` builds the draft input from Incident fields only. 23.10 added "Incident state: <state>" (underscores read as spaces) after the Production line, and `SYSTEMNOTE` carries 23.10's sentence. Both change in 23.11.
- `IncidentManager.DraftRequest` puts Facts in the text and `SYSTEMNOTE` in the system note. The mock log holds both.
- The demo contact (`Fix.PartnerContacts`, demo-only fixture) is now "Orders Partner IT" <it@orders-partner.example>, id 1, on the Orders production.
- Do not rename the inbound sample email from "Results Partner IT" <it@results-partner.example>.
- Delivery goes only to `SimMailboxOut`, byte for byte as approved, never through `EmailOut`.
- Pins live in `Test.Fix.PartnerWarning` (the SYSTEMNOTE pin, `TestFacts`), `PartnerDraft` and `PartnerTurns` (marker-driven `Asked`/`ResolvedIncident`, `TestResolvedDraftSaysTheOrdersWentThrough`).
- Mock scenarios: `ci/mock/scenarios/A/partner-notice*.json`, selected by marker. A new B prompt must not be contained in the instruction text.

**Records the Outcome fact can use (AD-16).**
- Each approved request gets its own `FixRun`, so an incident can have several (later requests).
- The final `FixResult` carries `Total`, `Resent`, `Completed`, `FailedAgain`, `Skipped`, `Interrupted`, `Unreached` and `Reason`.
- `Skipped` counts every target not resent, so it includes `Unreached`.
- Other endings 23.11 must place:
  - an interrupted run, which also resolves the incident;
  - a couldn't-start run (`Resent` 0, row `failed`);
  - a resend still in progress after the 60-second wait;
  - a resume.
- Item kinds report one result per item.
- `fixing` + a final `FixResult` resolves whatever the counts are.

**Incidents and fixes (AD-15, AD-16), for 23.9.**
- `IncidentManager` is the only writer of `Incident` and `FailureGroup` and the only publisher of `incident` events. Every state move goes through `Watch.Transitions`, and its unit test covers every row and every refused move.
- Today anything on a closed incident is refused, and `resolved` goes to `closed` on `closeQuiet`, `dismiss` or `closeForReplay`.
  - Option (b) changes the close rows, `Checks`' 15-minute `closeQuiet` among them.
  - Option (a) follows partner warning's `MOVES` 0 precedent.
  - Either way, the table, its test and the spine's AD-15 text change together.
- `FixExecutor` runs only an approved, unexpired, not-executing row. It re-checks each target, switches namespace in its one method and calls `Ens.Director.EnableConfigItem`. Each action is audited through `Bridge.Audit`.
- `Checks.Process.Findings` attributes OcuTalon's own suspend through `Fix.Run.Suspended`.
- The summary is composed in code on every move into `closed`, so option (b) delays it.
- A new item, table, row type or event type goes into the spine's ownership tables in the same change.

## UX & Interaction Patterns

- **Partner request card.** It is an extra approval request in the incident card. It shows the exact text and the simulated recipients, and the approved notice goes to the Simulated mailbox. No text may imply that a real email was sent.
- **Suspend, resume and reroute.** The request card shows its dry run (item state before and after) and ends "Nothing has changed yet." while pending. An approved run gets a result band ending "Recorded in the IRIS audit log."
- **Closed incident card.** It is compacted to its headline and each request's result. Under option (a), a resume on a closed incident must fit that card. Under option (b), the incident stays open and shows Dismiss.

## Cross-Story Dependencies

- Order on Lane D: 23.10 (done), then 23.11, then 23.9.
- 23.11 reworks 23.10's Facts state line, its `SYSTEMNOTE` sentence and the `partner-notice-resolved` mock case. It reads the `FixRun`/`FixResult` records written by 23.2 and Epic 7.
- 23.9 builds on:
  - 23.2's kinds, `propose_fix`, `Fix.Run.Suspended` and `result.itemSuspended`;
  - 23.6's summary-on-close;
  - 23.7's `Checks` tick, which sends `closeQuiet`.
- The (a)/(b) choice for 23.9 goes to the Contest Planner at the spec gate.
- The rail lag after Reject is DW-1159, outside these stories.
- 23.3 waits on Story 36.1, and 23.4 and 23.8 wait on Story 36.2. 24.2's partner-contact table will later replace the 23.5 fixture.
