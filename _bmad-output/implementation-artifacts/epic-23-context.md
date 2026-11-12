# Epic 23 Context: Deeper IRIS watch (step 5)

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Make OcuTalon watch IRIS more deeply and act on incidents more usefully. That means approved fixes beyond repair and resend (suspend, resume, reroute), partner delay notices sent only after approval, a written summary when an incident closes, and (Could) background checks that report between digests. Stories 23.2, 23.5, 23.6, 23.7, 23.10 and 23.11 are done. This compile serves the next story, **23.9**: a suspend that OcuTalon made gets a governed way back after its incident has closed, so an item is never left disabled with no approved path to resume it (ledger DW-1068). Stories 23.3, 23.4 and 23.8 wait on Epic 36 and are out of scope.

## Stories

- Story 23.2: Suspend, resume and reroute with a dry run (done)
- Story 23.3: Setting-change cause and rollback (waits on Story 36.1)
- Story 23.4: Paging and escalation (waits on Story 36.2)
- Story 23.5: Partner delay notices sent only after approval (done)
- Story 23.6: Incident summary when an incident closes (done)
- Story 23.7: Watch queue backlogs between digests (done)
- Story 23.8: Saved SQL query watch (waits on Story 36.2)
- Story 23.9: Resume a suspended item after its incident closes (next)
- Story 23.10: Partner notice and summary polish from the 1.0.7 demo pass (done)
- Story 23.11: Say in a partner notice only how the incident ended (done)

## Requirements & Constraints

**Resume after close (23.9).**
- It applies to an item that OcuTalon suspended through an executed `suspend_item` request of an incident the user can see, after that incident has closed. The user asks in the chat to resume the item.
- The spec chooses one option. The Planner leans to (b).
  - (a) The resume request is raised on the closed incident and never moves the incident's state.
  - (b) An incident with an active suspend stays open until a resume or a Dismiss.
- Whichever option the spec picks:
  - exactly one approval request with its own dry run is raised;
  - the item is re-checked before the resume runs;
  - a second session, or a user outside the incident's ownership scope, cannot resume the item.
- Undoing a suspend is one approved action. No risky action runs without an approved request, and a dry run changes nothing.
- Approval rules: requests expire after 24 hours and the first answer from any channel wins. A rejection or expiry changes nothing, and the user is told. On a local install before step 6, a user with the OcuTalon user role may answer a request they can see: their own, or one for a production they watch.
- Incident lifecycle today:
  - A resolved incident closes after 15 quiet minutes, by Dismiss, or by the replay rule (Break the feed in demo mode).
  - An open incident closes by Dismiss, and also after 15 quiet minutes when demo mode is off.
  - An incident that is awaiting approval or fixing never closes on its own.
  - A failure with the same cause after closing opens a new incident.
- **Ruled public text 23.9 touches:**
  - `result.itemSuspended` limits the undo to "while this incident is open" and points to the Management Portal after the incident closes. The README bullet has the same limit.
  - The `Agent/Chat.cls` resume instruction line still awaits ruled wording.
  - Any changed user-facing line goes to the Contest Planner verbatim before commit.
- On the online demo, suspend and resume are refused for every item (`ONLINESHARED`), because every visitor shares the Orders production. 23.9 therefore applies to local installs, with or without demo mode. Items of OcuTalon's own production are refused (`OWNPRODUCTION`).

## Technical Decisions

**Incidents (AD-15).**
- `IncidentManager` is the only writer of `Incident` and `FailureGroup` rows and the only publisher of `incident` events. Others ask it through an `IncidentCommand` (`dismiss`, `closeForReplay`, `closeQuiet`), an `ApprovalOutcome` or a `FixResult`.
- One transition table governs every move, and its unit test covers every row and every refused move. Today anything on a closed incident is refused.
- Whichever option the spec picks, the table, its test and the spine's AD-15 text change together:
  - (b) changes the close rows: `Checks`' `closeQuiet`, `closeForReplay` and `dismiss` on a resolved incident.
  - (a) follows the partner-warning precedent: its kind has `MOVES` 0, so raising or answering the request changes no incident state.
- The summary is composed in code and stored on every move into `closed`, then sent as a `summary` notification. Under (b) the summary waits for the resume or the Dismiss. Under (a) it is already written before the resume runs.

**Fixes and approvals (AD-11, AD-16, AD-17).**
- `Approval.Raise` creates the row with `IncidentRef`, fixed targets, the exact change, the stored `DryRun`, `OwnerRef`, a 24-hour expiry and `ResultTarget` (`IncidentManager` for incident fixes). The row's state changes only through the Approval API.
- `FixExecutor` loads everything from the approved row. It runs only a row that is approved, unexpired and not already executing, and only when the service user holds the kind's `RESOURCES` (`%Ens_ConfigItemRun:U`).
- `Recheck` skips and reports a target that changed since the dry run. The item is enabled through `Ens.Director.EnableConfigItem` from `FixExecutor`'s one namespace-switching method.
- Item kinds report a `FixResult` with Total 1, Resent 0 and Completed equal to the number of items changed.
- `Bridge.Audit` is the only audit writer. Each entry names the acting IRIS user, the `SessionRef` and the channel.

**Ownership (AD-4).**
- An `instance` incident belongs to every session that watches its production. `Data.Session.Recipients` resolves those sessions, and every read and command goes through `Data.Ownership`. No endpoint accepts a `SessionRef` from the client.

**The 23.2 path that 23.9 extends.**
- The chat tool `propose_fix` submits a `ProposeFix` command. `IncidentManager.Asked` runs one synchronous dry run, then raises the request through `RaiseFix`.
- `Asked` answers `not_found` for an unknown or closed incident, or for a session that is not a recipient. The tool resolves only open and resolved incidents (`FIXABLE`), so after close `resume_item` answers `no_incident`.
- `already_asked` covers a pending or approved request of the same kind with the same parameters. This is the "exactly one" rule.
- `Fix.Run.Suspended` ignores incident state. `Checks.Process.Findings` keeps an OcuTalon suspend in `ours`, so it never raises a disabled-item finding for that item, even after the incident closes (the second half of DW-1068).

**Notifications (AD-32).**
- Producers never render text. All wording comes from catalog keys (`Catalog.Watch` for results), and a new or changed key needs ruled text.
- A new item, table, row type or event type goes into the spine's ownership tables in the same change.

## UX & Interaction Patterns

- **Request cards.** Suspend and resume use the approval request card with their own dry run: the item and its state before and after. A pending card ends "Nothing has changed yet." After a run, each request card shows its own result band (`result.itemResumed`, `itemSkipped` or `itemNotChanged`).
- **Closed incident card.** It is compacted to its headline and each request's result, and its only action is Show details. Under (a), a new resume request card and its result have to fit this card. Under (b), the incident stays resolved and keeps Dismiss.
- **The guide.** It says "On your own install, suspend and resume work the same way". The online demo offers only the reroute.

## Cross-Story Dependencies

- 23.9 builds on:
  - 23.2's kinds, `propose_fix`, `Asked`, `Fix.Run.Suspended`, `result.itemSuspended` and the Checks `ours` suppression;
  - 23.6's summary on close;
  - 23.7's `Checks` tick, which sends `closeQuiet`.
- The (a)/(b) choice and any changed public text (`result.itemSuspended`, the README sentence, the chat resume line) go to the Contest Planner at the spec gate.
- 23.3's rollback kind and its undo follow the same item-target and undo contract. Whatever 23.9 decides about undo after close will likely set the precedent for undoing a rollback after its incident closes.
- 23.3 waits on Story 36.1, and 23.4 and 23.8 wait on Story 36.2. Later, 24.2's partner-contact table replaces the 23.5 fixture.
