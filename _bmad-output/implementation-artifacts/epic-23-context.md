# Epic 23 Context: Deeper IRIS watch (step 5)

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Make OcuTalon watch IRIS more deeply and act on incidents more usefully: approved fixes beyond repair and resend (suspend, resume, reroute, setting rollback), a written summary when an incident closes, partner delay notices sent only after approval, and (Could) background checks that report between digests. This compile serves a scope reopen for two stories, in this order: 23.7, which adds a queue-backlog background check so a stuck queue is reported between digests rather than waiting for the next digest; then 23.9, which gives a suspend OcuTalon made a governed way back after its incident has closed, so an item is never left disabled with no path to resume it. Stories 23.6, 23.2 and 23.5 are done and merged. Stories 23.3, 23.4 and 23.8 wait on Epic 36 and are out of scope.

## Stories

- Story 23.2: Suspend, resume and reroute with a dry run (done)
- Story 23.3: Setting-change cause and rollback (waits on Story 36.1)
- Story 23.4: Paging and escalation (waits on Story 36.2)
- Story 23.5: Partner delay notices sent only after approval (done)
- Story 23.6: Incident summary when an incident closes (done)
- Story 23.7: Watch queue backlogs between digests (in scope, first; Could)
- Story 23.8: Saved SQL query watch (waits on Story 36.2)
- Story 23.9: Resume a suspended item after its incident closes (in scope, second)

## Requirements & Constraints

**Queue-backlog watch (23.7)**
- Starting and stopping it are chat requests. Starting or stopping a background check the user asked for is a safe action: it needs no approval, and it goes through a tool that submits a command, never a direct table write.
- The check is a row in the one background-check table, owned by the session. Like every check it shows its schedule, last run and last result in the background-check list. Asking to stop removes the row.
- Each run reads every queue in each namespace whose data database the service user may read. On the online demo that is only the Orders production's queues.
- A queue is above its threshold when it holds more than 100 messages, or when its oldest message has waited more than 10 minutes. Admins can change both values, and they are the same thresholds the digest's coverage uses.
- Each queue above its threshold becomes one finding Item sent to `Intake`, where it gets one attention decision.
- No finding is reported twice. A queue already reported is not reported again until it has fallen below the threshold and then risen above it again: one finding per crossing.
- A run that fails, or that can't read a namespace, records "not checked" with the reason. It never records "passed", and it never feeds an all-clear.
- The check changes nothing on the instance (read-only, and no data-changing SQL).
- Tests live in `OcuTalon.Test.Checks`. Fill a test production's queue past its threshold and drain it twice: exactly one finding per crossing, each one with a decision.

**Resume after close (23.9)**
- Applies to an item that OcuTalon suspended through an executed `suspend_item` request of an incident the user can see, after that incident has closed.
- The spec must choose between two options, and the Contest Planner leans to (b):
  - (a) a resume request raised on the closed incident that never moves the incident's state;
  - (b) an incident with an active suspend stays open until a resume or Dismiss.
- Either way, the user gets exactly one approval request with its own dry run, the item is re-checked before the resume runs, and nothing changes until the request is approved.
- A second session, or a user outside the incident's ownership scope, cannot resume the item.
- Background (DW-1068, owned by 23.9):
  - `propose_fix` resolves only `open` and `resolved` incidents (`WatchTools` `FIXABLE`), so after close it answers `no_incident`.
  - `Fix.Run.Suspended` ignores incident state, so `Checks` keeps treating the item as "ours" and never reports it as disabled.
  - The ruled `result.itemSuspended` text limits the undo to while the incident is open and points to the Management Portal after it closes. Any change to that text, the README sentence, or the `Agent/Chat.cls` resume line is public text and needs a ruled wording.
- On the online demo, suspend and resume are refused for every item (`ONLINESHARED`), because every visitor shares the Orders production. Only reroute is offered there.

**Rules for every story in the epic**
- No risky action runs without an approved request. Resume is risky.
- A rejected or expired request changes nothing, and the user is told.
- Requests expire after 24 hours.
- The first answer from any channel wins.

## Technical Decisions

**Every command is a production message.**
- State changes enter through `CommandsIn` via `Commands.Submit`, which sets the origin. Origin `tool` is accepted only for listed verbs, and "start or stop a watch" is one of them.
- A tool's command carries an `IdempotencyKey`, and its owner ignores a repeat.
- `WatchOps` (`OcuTalon.Watch.Ops`) is the one creator of `BackgroundCheck` rows. It sends `Checks.Msg.CheckChanged` after a start or stop. `Checks` is the only writer of the run fields and the only publisher of the `check` live event. Lane A owns `BackgroundCheck`.

**Namespaces and reads.**
- Only `OcuTalon.Watch.Reader` reads other namespaces (headers, event log, settings, queues, vital signs), in one `New $NAMESPACE` method.
- It reads a namespace only if the service user holds read access on that namespace's data database.
- Pointer: `Watch.Reader.Failures(...)` already returns `queues`, one `{name, count, oldestAt}` per item with Status-2 (Queued) messages. It returns `""` instead of an array when the queues could not be read, so a caller never mistakes an unread queue for an empty one.
- Only `Fix.Executor` switches namespace to change an item, through `Ens.Director.EnableConfigItem`.

**Background checks (`Checks`).**
- `OcuTalon.Data.BackgroundCheck` is the one table for all checks. Each row has a `Kind`. Readers that filter on `Kind` `production` must keep working when a new kind is added.
- On each one-minute heartbeat `Tick`, `Checks` runs every due check once, even if it missed several runs. Each run records its last run, result and trace header id. Each run also INSERTs one `Digest.Data.CheckRun` row, which feeds the digest's coverage.
- Only new findings become Items.
- Pointer: production-watch findings already follow this pattern in `Checks.Process`. Each finding is an `OcuTalon.Msg.Item` with:
  - channel `system` and provenance `untrusted`;
  - the row's `SessionRef` as owner;
  - a catalog key and slots, because producers never render text;
  - its own trace session, with the session's `TraceRef` as `SuperSession`.
- Pointer: the crossing memory for production watches lives in `BackgroundCheck.Reported` (JSON).
- The spine names no queue-backlog row type yet; Story 36.1 was meant to add it. 23.7 must add it to the spine's background-check rule in the same change, as Story 35.1 did for source polls (columns appended, one creator class).

**Thresholds.**
- The digest's install step seeds `checks.thresholds.*` in `OcuTalon.Data.Setting`. Checks read them through `Data.Setting.Get` on every run, so an admin's change takes effect after the 60-second cache expires.
- Pointer: `OcuTalon.Checks.Coverage` already carries `queueMessages=100` and `queueWaitMinutes=10` (`THRESHOLDS`) and the finding text "{count} messages queued". The digest's per-production entry already includes queue backlog over threshold. 23.7 should reuse these and must not fork them.

**The all-clear comes only from code.**
- Check results are passed, failed with the finding, or not checked with the reason, and they come only from `OcuTalon.Checks`.
- `Checks.Render` and `Coverage.Build` alone decide an all-clear. Each background check of the session is an entry in the coverage list.
- An entry counts as checked only if it ran successfully throughout the window.

**Incidents.**
- `IncidentManager` is the only writer of `Incident` and `FailureGroup` rows and the only publisher of `incident` events. Other code reaches it through `IncidentCommand`, `ApprovalOutcome`, `FixResult` or `ProposeFix`.
- Every state move goes through the one transition table. Anything on a closed incident is refused today, so option (b) or a closed-incident request in option (a) is a ruled change to that table and its unit test.
- A partner-warning request already shows the precedent of a request that never moves state (its kind has `MOVES` 0).
- On every move into `closed`, the incident summary is composed and stored.
- A failure of a copy that a fix registered is attributed to that fix, never to a failure group. A suspend that OcuTalon made never shows up as a new state change.

**Fixes.**
- Fixes come from a fixed set of kinds under `OcuTalon.Fix.Kind`: `DryRun`, `Recheck`, `Execute`, a parameter schema and declared `RESOURCES` (`%Ens_ConfigItemRun:U` for the item kinds).
- The dry run is stored on the `ApprovalRequest` row. Item kinds use the keys `item`, `before` and `after`.
- `FixExecutor` runs only from an approved row that has not expired and is not already executing. It re-checks the target and skips it, with a report, if it changed.
- Each action is audited through `Bridge.Audit`, the only writer to the audit log.
- Undoing a suspend raises exactly one `resume_item` request (the `already_asked` rule).
- Pointers: `Fix.Run.Suspended(namespace, production, since, .fresh)` and `Watch.Notice.ResultKey` (the item result keys).

**Ownership and retention.**
- A session sees only its own incidents. On the online demo only the Orders production can be watched.
- A new item, table, row type or event type goes into the spine's ownership tables in the same change.
- Rows are purged through the standard purge task.

## UX & Interaction Patterns

**Background-check row.** One row per check in the status rail's "Background checks (n)" section: the check's name, its schedule, last run, last result, and a trace link to the latest run. The rows are read-only, with a stop hint ("To stop, ask: …"). While the heartbeat is stalled, the row reads "Last run {time} (late)". A queue-backlog check gets a row like every other check.

**Findings and decisions.**
- A finding Item gets one attention decision: ignore, digest, tell now or act. Tell now goes to the web chat, the simulated phone in demo mode, and the paired chat.
- Items that the user didn't send can on their own lead only to read-only checks, notifying the user, or saving for the digest.
- The newest decisions appear as decision rows with their reasons, cost and a trace link.
- Digest coverage wording follows the existing "Failed: {entry} ({finding}, at {time})" and "Not checked: {entry} (…)" lines. Only code ever says that everything passed, and the reserved all-clear sentences are never model-written.

**Approvals with dry runs.**
- Suspend, resume and reroute use the approval request card with their own dry run. For item kinds, the dry run shows the item and its state before and after, and ends "Nothing has changed yet." while pending.
- The card carries the fixed-targets line, the expiry, Approve and Reject (one press each), and its answered status, for example "Approved from {channel} at {time}" or "Rejected … Nothing was changed."
- Each approved request card in the incident card carries its own result band, followed by "Recorded in the IRIS audit log."
- A closed incident card is compacted to its headline and each request's result. If 23.9 chooses option (a), a resume raised on a closed incident has to fit this compact card. If it chooses option (b), the incident stays open and shows Dismiss.

## Cross-Story Dependencies

- 23.7 needs Epic 17's `checks.thresholds.*` keys (Epic 17 is done) and the admin Check thresholds section from Story 33.2. It does not wait on Epic 36, but it has to write the queue-backlog row type into the spine itself.
- At spec time, judge how much of 23.7 overlaps the queue reads already delivered in `Watch.Reader` and `Checks.Coverage`.
- 23.9 builds on 23.2's kinds, `propose_fix`, `Fix.Run.Suspended`, the attribution of OcuTalon's suspends in `Checks.Process.Findings`, and the ruled `result.itemSuspended` text. It also touches 23.6's summary, which is composed on every move into `closed`. The choice between (a) and (b) goes to the Contest Planner at the spec stage.
- 23.3 waits on Story 36.1. 23.4 and 23.8 wait on Story 36.2.
