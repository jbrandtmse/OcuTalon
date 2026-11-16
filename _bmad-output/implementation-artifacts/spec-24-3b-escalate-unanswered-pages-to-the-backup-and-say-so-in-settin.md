---
title: 'Story 24.3b: Escalate unanswered pages to the backup, and say so in Settings'
type: 'feature'
created: '2026-11-16'
status: 'done'
baseline_revision: '3fbccd77377f87d4c0d7efbfa0a418fc0e31a891'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-24-context.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-24-3a-deliver-pages-on-the-on-call-channels-and-take-the-web-ackno.md'
warnings: [oversized]
deferred: []
---

<intent-contract>

## Intent

**Problem:** Story 24.3a delivers pages and takes the web acknowledgement, but an unanswered page never reaches the backup: `ReminderOps` answers the paging owner's escalation ask with `not_built`. The Settings On call line still describes the pre-24.3 behaviour, GUIDE has no on-call bullet, and DW-1384's escalation-ask test asserts `not_built`.

**Approach:** carry the rest of the old Story 24.3 (epics.md `### Story 24.3b`): the escalation timer in `ReminderOps`/`ReminderTimer` with V1's `Data.Reminder` columns and `Data.Purge` part, re-armed by the startup reconciler exactly once; the approved On call line (Option A, verbatim) with its pins; the approved GUIDE bullet; DW-1384. The plan stage derives the rest from the epic, the parent 24.3 plan and Story 24.3a's spec (its Design Notes list what moved here).

</intent-contract>

## Boundaries & Constraints

Derived by the plan stage from the intent above, epics.md `### Story 24.3b`, the BINDING rulings quoted under Spec Change Log, the parent 24.3 plan and 24.3a's Design Notes › Moved to Story 24.3b.

**Always:**
- **The escalation ask (AD-18, AD-1).** `ReminderOps` handles a `SetReminder` of `Kind` `escalation` before any session check:
  - It accepts it only from origin `system` (the paging owner) and never on the online demo. Any other origin, and the online demo, answer Ok 0 `not_allowed` with `CommandsIn.#MESSAGENOTALLOWED`, and nothing is written.
  - It needs a non-empty `IncidentRef` and `PageRef`, a whole `DelaySeconds` above 0, and no `DueAt` or `LocalDueAt`. Anything else answers `refused` `bad_time` and stores nothing.
  - **One row per page (V2: at most one escalation to the backup per page).** If a row of `Kind` `escalation` already names the `PageRef`, in any state, the answer is that row's `set` with its Ref and DueAt, and no row or waiter is added.
  - Otherwise it saves one `Data.Reminder` row with `SessionRef` `instance` (always, whatever the command's SessionRef), `Kind` `escalation`, both Refs, `Text` "", DueAt = now + DelaySeconds, `pending`. It then starts one `ReminderTimer` waiter whose SuperSession is empty, publishes no live event, and answers Ok 1 `set` with the Ref and DueAt. A failed start deletes the row and answers `failed`, as for a reminder.
  - `Kind` neither "", `reminder` nor `escalation` still answers `not_built`.
- **Due (AD-5, AD-18).** `Schedule.Reminder.Wake` handles a pending escalation row under the row's exclusive lock, as it handles a reminder:
  - it marks the row `fired` (with `Late` as for reminders) and saves it;
  - it then sends one `OcuTalon.Msg.Escalation` (`IncidentRef`, `PageRef`) asynchronously to `IncidentManager`.
  - It sends no Notification and publishes nothing. A non-pending row sends nothing, so two waiters of one row send one Escalation. A failed send is logged with the Ref only and is not retried.
- **Cancel.** A `CancelReminder` from origin `system` whose `ReminderRef` names a pending escalation row cancels it without a session check:
  - `cancelled` under the lock, with the command's key as `CancelKey`;
  - then its waiter is ended at once (`EndWaiter` with an empty SuperSession), and nothing is published.
  - Any other case keeps today's session path. So an escalation Ref from a session origin is `no_reminder`, and a non-pending escalation row is `no_reminder`.
- **Restart (V1c).** `Reminder.Reconcile` re-arms a pending `instance` escalation row whose waiter is gone, through `Rearm`/`StartFrom` with an empty SuperSession, and never skips it as sessionless. A row with a live waiter is left alone (`LiveWaiter`). So each start re-arms each lost waiter exactly once, a second pass starts nothing, and a timer due during downtime fires once right after the start. A restart never sends a second Escalation for a row.
- **Lists.** No escalation row appears in any session's `ListReminders`, reminder event, `/state`, rail or heartbeat snapshot. All of them read `WHERE SessionRef = ?` through `Data.Ownership`, and `instance` is never a session.
- **Purge (V1c, AD-27).** `Data.Purge.Run` gains one part. It deletes rows with `SessionRef` `instance`, `Kind` `escalation`, `State` `fired` or `cancelled`, and `CreatedAt` before the cutoff, and nothing else. A pending escalation row, a newer one and every session reminder row are untouched by this part.
- **Online demo (V1c).** Nothing is written: ReminderOps refuses before any read or write of the table, so no row, no waiter and no ReminderStart.
- **Ids only (AD-19, NFR-11).** The new rows, messages and log lines carry Refs, codes and counts only. They never carry an address, a user name, a chat id or a display name.
- **The On call line.** It is the approved new text 1 (Public text) verbatim. It replaces DW-1400's line, is shown while `pagesBuilt`, and is pinned in `ux-strings.test.mjs`, `on-call-view.test.mjs` and O1.
- **The GUIDE bullet.** It is the approved P4 text verbatim, using GUIDE.md's existing separator `Settings > …`. There is no More-to-try item.
- **Storage** is append-only, with committed storage blocks (AD-5).

**Never:**
- Edit `Watch/**`, `Data/Page.cls`, `Install/**`, `Msg/Catalog/**` or `Channel/Telegram/**`. The only Lane A edit is `Test/Watch/PagingLive.cls` `TestEscalationAsk` and that file's doc lines for it (V5, DW-1384).
- Edit the spine. The lead applies the OLD/NEW under Design Notes › Spine updates.
- Add a verb, a route, a table, an index, a catalog key, a production item, a CI group or unit, or a web dependency.
- Add a refusal Message, or change `MESSAGENOTALLOWED`, `MESSAGENOTBUILT` or any reminder text.
- Make a timer outside `ReminderTimer` (AD-5). Publish a live event for an escalation row. Give an escalation row a session.
- Delete a pending escalation row, or a session's reminder row, in the new purge part.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Ask | SetReminder {Kind escalation, IncidentRef I, PageRef P, DelaySeconds 600} from `system` | Ok 1 `set`, Ref R, DueAt now+600; one row (instance, pending, Kind, I, P, Text ""); one live waiter whose start header comes from ReminderOps with an empty SuperSession; no live event | a failed start deletes the row and answers `failed` |
| Ask with a session | the same, SessionRef = a fixture session S | the row's SessionRef is `instance`; S's ListReminders shows nothing | none |
| Ask again | the same P again, any state of the first row | the first R and DueAt; one row, one waiter | none |
| Not system | the same from web_user, web_admin, telegram, timer, or tool (a bridge context), a session given or missing | Ok 0 `not_allowed` with MESSAGENOTALLOWED; no row names P; no waiter | refusal by code, before the session lookup |
| Bad fields | empty I or P; DelaySeconds "", 0, -5 or "x"; DueAt or LocalDueAt set | Ok 0 `refused` `bad_time`; nothing stored | none |
| Other kind | Kind `other`, any origin | Ok 0 `not_built` (unchanged) | none |
| Online demo | `onlineDemo` 1, a valid system ask | Ok 0 `not_allowed`; no row, no ReminderStart, no ReminderTimer | refusal by code |
| Due | waiter wakes at DueAt, row pending | row `fired` (Late as for reminders); exactly one `Msg.Escalation` {I, P} from ReminderTimer to IncidentManager; no request to Notify; no live event | a failed send is logged with R, not retried |
| Two waiters | a second waiter started by `Rearm(R)` before due | one Escalation in all | none |
| Cancel | CancelReminder {ReminderRef R} from `system`, R pending | Ok 1 `cancelled`; row cancelled; the waiter ends at once (well before DueAt); no Escalation | R fired or cancelled: `no_reminder`, nothing changes |
| Cancel from a session | CancelReminder {R} from web_user with a session | `no_reminder`; the row stays pending | none |
| Restart | production stopped and started (ReconcileIn): A = lost waiter, past due; B = lost waiter, due in 1 h; C = set through the product with a live waiter, due after the start | A fires once (one Escalation, Late 1); B gets exactly one start header from HeartbeatIn (empty SuperSession) and one live waiter; C has exactly one live waiter and fires once; a second `Reconcile` adds no start header | none |
| Backup paged | real IncidentManager, an open incident, an unacknowledged on-call Page row P, the backup key set; ask with DelaySeconds 3 | exactly one backup Page row of the incident after due | none |
| Acknowledged first | the same, P acknowledged through `AckPage` before due (the row's Ref recorded with `Paging.Armed`) | IncidentManager's cancel makes the row `cancelled` and ends the waiter; no Escalation; no backup Page row | none |
| Purge | escalation rows fired, cancelled and pending, created before the cutoff; a fired one created after it; a finished session reminder of a kept session | only the old fired and cancelled escalation rows are deleted | as the other parts |
| On call line | `pagesBuilt` true | the new line verbatim, id `oncall-pages`; the DW-1400 line absent | none |

## Code Map

All paths are under `src/ocutalon/cls/OcuTalon/` unless they start with a top-level folder. Line numbers are from `d355ec59`.

**Escalation timer (Lane B, `Schedule/**`, `Data/Reminder.cls`, in paths_hint)**
- `Schedule/ReminderOps.cls`:
  - Class doc 3-32 (it describes the `not_built` guard; rewrite for the escalation path).
  - `OnMessage` 75.
  - `Set` 101-138: the guard is at 103. The row, waiter and publish steps at 111-137 are the sibling to extend.
  - `Cancel` 175-212, `IsPending` 215, `KeyedRow` 229 (SQL on its own table).
  - `EndWaiter` 246-265: it quits when there is no Session row (251-252), so an `instance` row needs an empty SuperSession.
  - `StartWaiter` 276-287: it errors with no session at 279.
  - `SendIn` 292, `Refuse`/`Done`/`Result` 318-340, `MESSAGESET` 46.
- `Schedule/Reminder.cls`:
  - Class doc 3-20.
  - `Wake` 123-160: the lock and the pending check at 126-134; it sends the Notification at 147-153 and publishes at 155.
  - `LiveWaiter` 164, `Rearm` 178.
  - `StartFrom` 192-210: it errors with no session at 199-200.
  - `Reconcile` 217-246: the SELECT at 222 has no Kind; it skips sessionless rows at 238-240.
  - Add parameters for the escalation target item (`IncidentManager`) and the owner `instance`. `instance` is a per-class Parameter elsewhere, e.g. `Live/Publish.cls:21`.
- `Data/Reminder.cls` 1-88: properties 9-37, storage values 1-11.
- `Msg/Command/SetReminder.cls:17`: the Kind doc says "Until Story 24.3 … not_built" (update the doc only).
- `Msg/Escalation.cls` (unchanged): IncidentRef, PageRef.
- `Core/CommandsIn.cls`:
  - `MESSAGENOTALLOWED` 87, `MESSAGENOTBUILT` 93;
  - the reminder verbs' origins include `system`, 344-346.
  - `Core/Commands.cls` `Submit` sets `command.Origin` (tool inside a bridge context), which reaches ReminderOps unchanged.
- Online demo: `Data.Setting.Get("onlineDemo") = 1`, as `Core/Rule/Functions.cls:78`.
- Production items (unchanged): `IncidentManager` (pool 1, a BP), `CommandsIn` (a BS, pool 0, in-process), `ReminderOps`/`ReminderTimer` (pool 1), `HeartbeatIn`. ReconcileIn reconciles every production start that the Production step did not make (`Install/ReconcileIn.cls`, Lane A, read only).

**Paging owner (Lane A, read only)**
- `Watch/IncidentManager.cls`:
  - `Arm` 2082-2098 asks the escalation from `system` (DelaySeconds = minutes x 60) and records `result.Ref` through `Paging.Armed`;
  - `Escalated` 2108 handles `Msg.Escalation`;
  - `Followed` 2141 cancels on a first acknowledgement while no backup page exists;
  - `Unpage`/`Cancel` 2158-2181 send `CancelReminder` from `system`.
- `Watch/Paging.cls`:
  - `Escalate` 171 refuses unless the incident is open, the on-call page is unacknowledged and no backup page exists (the unique `IncidentRoleIndex`);
  - `Closing` 280, `Armed` 293.
- These nested sync calls (IncidentManager → `Commands.Submit` → ReminderOps → ReminderTimer) are new at run time: `EscalationRef` was always empty before. See Task 0.

**Purge (Lane B Data area; outside paths_hint)**
- `Data/Purge.cls`: class doc 3-17; `Run` 26-35; `DeleteTurns` 38-48 is the part to copy in shape; the session-scoped Reminder delete is at 104 and the pending `Keeps` check at 133 (both unchanged).

**Tests**
- `Test/Schedule/Reminders.cls` (Lane B):
  - doc 27-31;
  - `TestEscalationNotBuilt` 668-722 and `TestEscalationGuardComesFirst` 724-771 assert `not_built` for escalations;
  - `RemoveTraces` 775 (a helper for commands with no SuperSession);
  - patterns: `TestTwoWaitersFireOnce` 1137, `TestReconcileWithoutProductionDoesNothing` 1229 (`SettleScheduler`, `StopProduction(10,0)`), `StartCount` 986.
- `Test/Schedule/ReminderFixture.cls`:
  - `Remove` 96-141 cancels a pending row through a session tool (`Cancel`), which an `instance` row refuses;
  - `Timers` 178, `WaitingCount` 197, `StartHeaders` 209, `WaitEnded` 221.
- `Test/Data/Fixture.cls`: `Reminder(sessionRef, dueAt, state, fields)` 82 (fields set any property), `Incident` 116.
- `Test/Core/InProduction` is the base of `Reminders` and `PageRoute` (Guard, sessions, Number).
- `Test/Watch/Paging.cls` (Lane A, use only):
  - `Write` 130, `User` 142, `Page` 213, `SaveKeys`/`PutKeysBack` 87/99, `Ack` 290;
  - its `Escalation` 281 builds a message.
- `Test/Channel/PageRoute.cls`:
  - doc 1-27;
  - `Keys` 254, `Incident` 265, `PageRow` 280, `Mails`/`WaitMails` 356/363, `AssertMail` 418;
  - `TestNoIdentityInTheTrace` is the identity-check pattern.
- `Test/Watch/PagingLive.cls` (Lane A): doc line 8, `TestEscalationAsk` doc 326 and body 327-346 (fixture Refs `zzpagelive-*`, DelaySeconds 900).
- `Test/Data/Tables.cls:527-545` (the Reminder contract).
- `Test/Data/Purge.cls`:
  - `TestOnlyOwnTablesAndAuditKept` 257 (the delete list at 315);
  - `Rows` 430, `Track` 394, `Cutoff` 364, `Ago` 371.
- `Test/Msg/Contracts.cls:68-71` already round-trips the SetReminder and Escalation fields (unchanged).

**Settings line (Lane B, in paths_hint except `web/scripts`)**
- `web/src/app/settings/settings-view.ts:102` `telegramOnly`.
- `web/src/app/settings/on-call-section.ts`: doc 43-44; template 64-68 (`@if (!pagesBuilt())` / `#oncall-telegram-only`).
- Pins:
  - `web/scripts/on-call-view.test.mjs:41` (deepEqual of the texts);
  - `web/scripts/ux-strings.test.mjs:1141-1143` (the approved entry with its source label);
  - `web/e2e/settings/on-call.spec.ts`: doc 15, const 44, O1 assertion 115 (the `sign-in-2` project).

**GUIDE (root doc; its pin is Lane B `docker/**`)**
- `GUIDE.md` `## New since 1.0.0` › `#### Your integrations`, lines 9-21. The separator in use is `Settings > Channels > Email` (16) and `Settings > Tools and MCP servers` (17-18).
- `docker/tests/test-readme.sh` rule `new-since` 1060-1130:
  - `NS_WANT` lists every bullet by bold name, in order; any new bullet fails as "unexpected" until it is listed.
  - `NS_T7`/`NS_FILE_BULLET` pin whole bullets.

## Tasks & Acceptance

**Execution:**
- [x] Task 0 (measure first; record under Design Notes › Measured, and label anything unmeasured "(inference)"). On a fresh lane-D throwaway, after the ReminderOps change:
  - (a) the real `IncidentManager` `Arm` chain with the waiter start (IM → `Commands.Submit` → ReminderOps → ReminderTimer): its time, and that nothing deadlocks;
  - (b) the nested cancel: an `AckPage` from `web_user` → IncidentManager `Followed` → `CancelReminder` from `system` → ReminderOps. Measure that it completes, and its time;
  - (c) whether a live ReminderTimer waiter survives `Ens.Director.StopProduction` and `StartProduction`, and how long the stop, the start and ReconcileIn's reconcile take.
- [x] `Data/Reminder.cls` -- append `Kind` (`%String(MAXLEN = 32)`), `IncidentRef` and `PageRef` (`%String(MAXLEN = 22)`), with docs. Append storage values 12-14 in the committed block. No index. -- AD-5, AD-18, V1.
- [x] `Schedule/ReminderOps.cls` -- the escalation path in `Set`, before the session check, as Boundaries › The escalation ask. Repeat detection is a `SELECT` by PageRef on its own table (Kind `escalation`). `Cancel`'s system branch is as Boundaries › Cancel. `StartWaiter` and `EndWaiter` use an empty SuperSession for an `instance` row. Rewrite the class doc. -- AD-1, AD-5, AD-18.
- [x] `Schedule/Reminder.cls` -- `Wake`'s escalation branch (as Boundaries › Due). `StartFrom` starts an `instance` escalation row with an empty SuperSession. `Reconcile` selects `Kind` and re-arms `instance` escalation rows instead of skipping them. Update the class doc. -- AD-5, AD-26.
- [x] `Data/Purge.cls` -- the new part `DeleteEscalations(cutoff)`, called from `Run` after `DeleteDeliveries`. Update the class doc's part list (the tables are unchanged). -- AD-27, V1.
- [x] `Msg/Command/SetReminder.cls` -- `Kind`'s doc states the contract as built (escalation from `system` only). Doc only; the storage is unchanged.
- [x] `web/src/app/settings/settings-view.ts` -- replace `telegramOnly` with `pages`, holding new text 1 verbatim.
- [x] `web/src/app/settings/on-call-section.ts` -- the template shows `texts.pages` with id `oncall-pages` while `pagesBuilt`. Update the doc at 43-44. `notYet` and `byEmailHelp` are unchanged.
- [x] `GUIDE.md` -- insert the approved P4 bullet verbatim in `#### Your integrations`, right after `**MCP tools as sources.**`.
- [x] Tests (each pinned with the mutation under Verification):
  - `Test/Schedule/Escalations.cls` (NEW; extends `Test.Core.InProduction`; throwaways and CI only). It covers Matrix rows Ask to Acknowledged first:
    - `TestAskMakesOneInstanceRow`;
    - `TestAskAgainSameRow`;
    - `TestOnlySystemMayAsk` (all five origins; tool through `ReminderFixture.Submit`; `Kind` `other` from system stays `not_built`; for a missing session the answer is `not_allowed`, not `no_session`);
    - `TestBadFieldsRefused`;
    - `TestOnlineDemoWritesNothing` (save and restore `onlineDemo` as `Test.Channel.EmailOut` does);
    - `TestNotInAnyList` (ListReminders, and the three `Data.Ownership` Reminder readers whose SQL is at 1236, 1361 and 1442, for the fixture session; the session's reminder events);
    - `TestCancelFromSystem`;
    - `TestDueSendsOneEscalation` (with a second waiter from `Rearm`);
    - `TestRestartRearmsOnce`: `SettleScheduler`, then `StopProduction(10,0)` and `Ens.Director.StartProduction`, so that ReconcileIn runs; wait for its Info row (`ReconcileIn.#LOGTEXT`); then an explicit `Reconcile(refs)` adds nothing;
    - `TestBackupPagedOnceUnlessAcknowledged`: the real IncidentManager, with a fixture incident (`Test.Data.Fixture.Incident`), on-call Page rows built as `PageRoute.PageRow` builds them, and keys through `Test.Watch.Paging.Write` (saved and put back).
    - Each test removes its rows, waiters and trace sessions.
  - `Test/Schedule/ReminderFixture.cls` -- `Remove` cancels a pending `instance` escalation row with `CancelReminder` from `system` (through `Commands.Submit`), then removes it as it does a reminder.
  - `Test/Schedule/Reminders.cls` -- delete `TestEscalationNotBuilt` and `TestEscalationGuardComesFirst` (now `Escalations`' tests), and their doc lines. Keep `RemoveTraces` if `Escalations` does not take it over (Rule 2: move it to `ReminderFixture` if both need it).
  - `Test/Watch/PagingLive.cls` (V5, DW-1384) -- `TestEscalationAsk` asserts that the system ask answers Ok 1 `set` with a Ref and a DueAt, and that one pending `instance` row of Kind `escalation` with the two fixture Refs and one live waiter exist. It still prints the timing. It removes the row through `ReminderFixture.Remove`. Update the doc lines 8 and 326.
  - `Test/Channel/PageRoute.cls` -- `TestEscalationMailsTheBackup` (the AC's Test.Channel test with the mock mail server):
    - an address-only on-call page row (email) and `oncall.backup.email` set; an escalation from `system` with DelaySeconds 3;
    - after due: exactly one backup Page row, and exactly one mail to the backup key's address (`AssertMail`), from the real path ReminderTimer → IncidentManager → Notify → EmailOut;
    - the SetReminder, ReminderStart and Escalation bodies, the Reminder row and the ReminderOps/ReminderTimer log lines since the mark hold no address, user name or chat id (the mock got the mail: the positive control).
    - Update the class doc.
  - `Test/Data/Tables.cls` -- the Reminder contract gains the three properties.
  - `Test/Data/Purge.cls` -- `TestFinishedEscalationsGo` (Matrix row Purge, with fixture rows through `Fixture.Reminder("instance", …, {"Kind": "escalation", …})`). Update `TestOnlyOwnTablesAndAuditKept` only if its statement list counts per statement.
  - `web/scripts/on-call-view.test.mjs:41`, `web/scripts/ux-strings.test.mjs:1141-1143` (the entry's label names the 24.3 rulings' new text 1, and the DW-1400 line is removed from the approved list), `web/e2e/settings/on-call.spec.ts` (const, doc 15 and the O1 assertion: the new line visible, the DW-1400 line count 0).
  - `docker/tests/test-readme.sh` -- `NS_WANT` gains `B On-call pages` after `B MCP tools as sources`. Add `NS_ONCALL`, the whole approved bullet, checked once and word for word as `NS_T7` is. Update the rule's doc comment (the bullet count).

**Acceptance Criteria:**
- AC1: Given the paging owner's escalation ask from `system`, when it is created, then one pending `instance` row of Kind `escalation` with both Refs and one live `ReminderTimer` waiter exist, and the answer carries its Ref and DueAt. A repeat ask for the page adds nothing. An ask from any other origin, with bad fields, or on the online demo writes nothing (`Escalations`, and `PagingLive` `TestEscalationAsk` for DW-1384).
- AC2: Given a pending escalation, when it falls due, then exactly one `Msg.Escalation` reaches `IncidentManager` and no Notification goes, even with two waiters. When `IncidentManager` cancels it from `system` first, the row is cancelled, its waiter ends at once and nothing is sent (`Escalations`).
- AC3 (Integration, Rule 1): Given an unacknowledged on-call page of an open incident with a backup configured, when its escalation falls due, then the real `IncidentManager` records exactly one backup page, and the backup's page reaches its route (one mail to the backup key at the SMTP mock). When the page is acknowledged through `AckPage` first, no backup page is recorded (`Escalations` `TestBackupPagedOnceUnlessAcknowledged`, `PageRoute` `TestEscalationMailsTheBackup`).
- AC4: Given pending escalation rows, when the production is stopped and started, then each lost waiter is re-armed exactly once, a timer that fell due fires exactly once right after the start, and a second reconcile starts nothing (`Escalations` `TestRestartRearmsOnce`).
- AC5: Given escalation rows, when a session lists its reminders or reads them through any reader, and when an escalation runs end to end, then none appears in any session's reminder list, reminder event or reader, and no message body, row or log line of the escalation path holds an address, a user name or a chat id (`Escalations` `TestNotInAnyList`, `PageRoute` `TestEscalationMailsTheBackup`).
- AC6: Given the daily purge, when `Data.Purge.Run` runs, then only the fired and cancelled escalation rows created before the cutoff are deleted (`Test.Data.Purge`).
- AC7: Given `pagesBuilt` true, when the On call section renders, then it shows new text 1 verbatim and not DW-1400's line (`on-call-view`, `ux-strings`, O1).
- AC8: Given GUIDE.md, when `test-readme.sh` reads it, then `New since 1.0.0` holds the approved On-call pages bullet once, word for word, after `MCP tools as sources` (`test-readme.sh` `new-since`).

## Spec Change Log

- 2026-11-16 (lead, after MERGE-BACK DONE). Merged feature e404c59d (1.0.12 merge-back with DW-1430) into OCT-epic24; `Channel/PageText.cls` add/add resolved to DW-1430's version (its class comment names the Telegram copy too). Contest Planner condition on the AD-14 amendment, relayed by the orchestrator: "on the online demo the page email answers OK while reading, writing and sending nothing. So NO demo surface (card, chat, timeline, digest) may claim that an email was sent or tried. Pin it with one assertion." Pinned in `Test.Channel.PageRoute:TestOnlineDemo` (helper `DemoClaims`: the incident payload's page part, the session's chat snapshot rows of the page, the email Delivery rows of the page of any owner, expected "0|0|0"). Mutation: `Watch.Paging.PagePayload` without its online-demo check -> only that assertion red; reverted `cmp`-identical.

- 2026-11-16 (lead). Chartered by the Contest Planner's P5 split of Story 24.3. The BINDING rulings (24.3 gate ~08:30Z and 24.3a Q1/Q2 ~12:30Z, Nov 16), quoted in full from `<coordination>/prompts/story-243-rulings-20261116.md`:

  > # DW-1426 and Story 24.3 rulings (Contest Planner, ~08:30Z on 2026-11-16). BINDING.
  > 
  > ## DW-1426: APPROVED as a small follow-up
  > - Once an undo is answered, announce the EXISTING "Approved/Rejected from…" text and move focus to the incident headline. No new string.
  > - Pin both behaviours, each with a mutation.
  > - It goes into 1.0.12 if it merges before the cut. It is not a cut item.
  > - The earlier ruling (a), "nothing once answered", was about drawing request cards. It was not about announcing the answer.
  > 
  > ## 24.3: NOT in 1.0.12
  > Merge 24.3a only AFTER the 1.0.12 cut. The gate is approved as follows.
  > 
  > ### P5: the split is APPROVED
  > - 24.3a: delivery and the web acknowledgement.
  > - 24.3b: the escalation timer, the On call line, DW-1384 and the GUIDE bullet.
  > - The On call line ships with 24.3b. Until then, DW-1400's line stands.
  > 
  > ### P1: Option A is APPROVED
  > - A page always gets a web chat card, and that card is not counted as a channel.
  > - Telegram and email follow the person's chosen channels exactly, with no fallback.
  > - A person given only as an address gets email only.
  > - An email copy is never marked handled.
  > 
  > Option B is refused.
  > 
  > ### P2: APPROVED
  > A not_paired delivery row that Paging reads.
  > 
  > ### P4: the GUIDE bullet is APPROVED as written
  > - No More-to-try item.
  > - Use the Settings separator GUIDE already uses elsewhere (› or >). Do not introduce a new one.
  > 
  > ### New text 1, the On call line: APPROVED verbatim (Option A version)
  > Keep its pins in ux-strings, on-call-view and O1.
  > 
  > ### Vetoes V1 to V6: APPROVED, with conditions
  > Pin each condition with a mutation.
  > 
  > - (a) V2, page email:
  >   - It goes ONLY to an address an admin set in Settings › On call. Never take an address from an item, the model or a message.
  >   - The body is built only from the fixed page keys: production, failure count, time and the OcuTalon link. No untrusted item or message text goes in verbatim.
  >   - At most one email per page row, and at most one escalation to the backup per page.
  >   - Trace, logs and audit carry ids only.
  >   - It is refused on the online demo in BOTH Notify and EmailOut.
  > - (b) V3, got-it:
  >   - It accepts only the session's OWN page copy.
  >   - Another user's page ref answers 404, exactly like a missing ref, so nothing reveals that it exists.
  >   - It answers 404 on the online demo.
  > - (c) V1, escalation timers:
  >   - They survive a restart and are re-armed exactly once, so a restart never pages twice.
  >   - The Data.Purge part removes only finished escalation rows, and purging the data removes them with it.
  >   - Nothing is written on the online demo.
  > - (d) V4: at merge, send the AD-14, AD-18 and AD-27 amendments as old text and new text.
  > - (e) V5 and V6: the orchestrator coordinates the Lane A and Lane B file overlaps.
  > 
  > ## Lane D order
  > 1. DW-1426 (small; can make 1.0.12).
  > 2. 24.3a: push it, but it merges after the cut.
  > 3. 24.3b.
  > 
  > Any 1.0.12 cut item that is still open comes first.
  > 
  > ## 24.3a Q1 and Q2 (Contest Planner, ~12:30Z Nov 16). BINDING.
  > 
  > ### Q1, the page email: ACCEPTED
  > Use the approved catalog texts as they are, with no link. Conditions:
  > - **Cause:** the diagnosed cause in the email is EXACTLY the sentence shown on the web card and in Telegram, after Bridge.Redact.Text and the same length cap. It is never raw item or message text.
  > - **Name:** the on-call or backup person's name exactly as an admin set it in Settings.
  > - **Pin it:** no item or message text reaches the email body. Add a mutation.
  > 
  > ### Q2: hold 24.3a until 24.3b is green
  > - 24.3a's merge is HELD until 24.3b is green.
  > - The two merge back to back, with no release cut between them.
  > - DW-1400's On call line stays true until then.

## Review Triage Log

### 2026-11-16 - Review pass
- verdicts: 29 findings - high 0, medium 3, low 22, false 4, maybe-false 0 (Intent Alignment Auditor: descriptive, no finding; it found no divergence from the intent)
- findings:
  - `[medium]` `patch` Blind (untested failure paths), Verification-gap (start failure; send failure and busy lock): the failed waiter start, the failed escalation send and the busy-lock cancel have no escalation test - the three added to `ReminderLogic` (`TestEscalationStartFailureKeepsNothing`, `TestWakeEscalationSendFails`, `TestCancelEscalationBusyRowFails`; `ReminderTimerDouble` reads a request's properties through `Field`, since an Escalation has no Kind), each with a mutation observed red.
  - `[medium]` `patch` (members of the entry above) Verification-gap: start failure of `Escalate` unpinned; send failure and lock-busy cancel unpinned - same fix.
  - `[medium]` `patch` (members of the entry above) Blind: the failure paths of the escalation documented in the class docs are not exercised - same fix.
  - `[low]` `patch` Blind, Edge: Purge's class doc says the escalation rows go "with the pages and incidents they name" - reworded: only the Reminder rows go.
  - `[low]` `patch` Edge: `ReminderOps.Escalate`'s repeat lookup does not check `%SQLCODE`, so a failed read could add a second row - answers `failed` when the read fails.
  - `[low]` `patch` Edge: `Reminder.Escalate`'s doc says the row is let go before it returns while Wake still holds its lock - reworded: the lock is Wake's.
  - `[low]` `patch` Blind, Edge, Verification-gap: `TestEscalationMailsTheBackup` opens the Reminder row without an `$IsObject` check - guarded; an early `Quit` before the ask leaves no escalation row, and the base class removes the page rows.
  - `[low]` `patch` Verification-gap: `TestDueSendsOneEscalation`'s body check is conditional - it now asserts that exactly one Escalation body was read.
  - `[low]` `patch` Verification-gap: `TestCancelFromSystem`'s fired-row cancel asserts only `refused` - it also compares the no_reminder Message.
  - `[low]` `patch` Verification-gap: AC3's acknowledged-first half has no recorded mutation - recorded and observed red (`CancelEscalation` answers no_reminder without cancelling -> `TestBackupPagedOnceUnlessAcknowledged` case B).
  - `[low]` `reject` Blind, Edge: a repeated CancelReminder from system with the same key answers no_reminder - Boundaries > Cancel says a non-pending row is no_reminder, the row is cancelled either way, and a replay branch adds code for a retry that IncidentManager does not make.
  - `[false]` `reject` Blind, Edge, Verification-gap: "at most one row per page" has no unique index and a SELECT then INSERT race - `ReminderOps` runs with pool size 1 (Code Map), so asks are serialized; the spec forbids a new index; `IncidentRoleIndex` is the second guard.
  - `[low]` `reject` Blind: a failed or lost send drops the backup page - spec-bound: Boundaries > Due says a failed send is logged and not retried, so that a restart never pages twice (V1c).
  - `[low]` `reject` Blind: `Wake` keys on Kind alone, `Armable` and `IsEscalation` also on the owner - no code path makes a session-owned escalation row (`Escalate` forces `instance`); only the purge test's fixture does.
  - `[low]` `reject` Blind: the `telegram-demo` mutation test's name - a test label; the mutation is red and the exemption is pinned to the exact line.
  - `[low]` `reject` Blind: the removed `Reminders` tests dropped two small controls - Kind `other` from system stays pinned in `TestOnlySystemMayAsk`, and an explicit Kind `reminder` takes the unchanged reminder path that every `Reminders` test covers.
  - `[low]` `reject` Blind: doc comments read as run-on sentences - cosmetic.
  - `[low]` `reject` Verification-gap: `TestNotInAnyList` `/state` check has no positive control - the pinning assertion is the session's `ListReminders` and the three readers, with a recorded mutation; the `/state` check is a further guard.
  - `[low]` `reject` Verification-gap: `TestAskAgainSameRow`'s waiter and header assertions after each state flip restate the first one - harmless repetition.
  - `[low]` `reject` Verification-gap: `TestRestartRearmsOnce`'s final check includes the fired row A - B and C carry it.
  - `[low]` `reject` Verification-gap: `PagingLive.TestEscalationAsk` uses fixed Refs and removes its row only at the end - the Refs and the edit are fixed by V5 (DW-1384); the row is removed on the success path and the stack is a throwaway.
  - `[low]` `reject` Verification-gap (other): no test pins `Armable`'s Kind half for a pending instance row of Kind empty - no code makes such a row.
  - `[false]` `reject` Verification-gap (other): no index on the Reminder lookup - the same finding as the unique-index one; the purge bounds the rows (Decided 3).
  - `[false]` `reject` Verification-gap (other): `COUNT(*)` readers in `Test.Tools.Reminders` and `Test.Demo.GuidePrompts` may meet leftover escalation rows - both compare a before and an after count of the same run, and both passed.

## Design Notes

### Rulings applied (24.3 gate and 24.3a Q1/Q2, BINDING)
- **P5:** this story carries the timer, the On call line, DW-1384 and the GUIDE bullet. 24.3a's merge is held until this story is green, and the two merge back to back (Q2).
- **New text 1** (Option A) is used verbatim. I compared it byte for byte with the parent 24.3 plan's Public text 1 (the approved form): identical, pure ASCII, straight apostrophe in "they're". No UX or catalog source holds the text.
- **P4:** the GUIDE bullet is used as written, with no More-to-try item. GUIDE.md's existing separator is `>` (`Settings > Channels > Email`), and the approved bullet already uses it.
- **V1 (c):**
  - re-armed exactly once: `LiveWaiter` skip, pinned by a second Reconcile;
  - never pages twice: pending check under the lock, pinned with two waiters;
  - finished rows only: the purge part;
  - nothing on the demo: the refusal comes first.
- **V2:** at most one escalation per page: one row per PageRef, fired once. IncidentManager's unique `IncidentRoleIndex` is Lane A's second guard.
- **V4:** the OLD/NEW below. **V5/V6:** Files below.

### Decided in-stage
1. **"Purging the data removes them with it"** is read as: the daily purge (`OcuTalon purge` → Retention → `Data.Purge.Run`) deletes finished escalation rows in the same run, with the same cutoff, as the incidents and pages they name.
   - An escalation row is created at page time, so its `CreatedAt` is at or before its incident's close. An incident closed before the cutoff therefore has its finished escalation rows before the cutoff too, whichever area's purge runs first.
   - The pending rows of a closed incident are cancelled by `Unpage`, or fire and are then finished.
   - So both readings hold with one SQL part, and no Lane A purge is edited. `TestFinishedEscalationsGo` pins an escalation row of a closed incident.
2. Bad escalation fields answer `refused` `bad_time`, as the parent plan decided, with no new Message. Only `system` sends it, and the Message is never shown.
3. Repeat detection is by PageRef across every state (a fired or cancelled row is still the page's one escalation), by SQL on ReminderOps' own table. There is no index: there is at most one row per page, and the purge bounds the rows.
4. `Kind` `other` keeps `not_built`.
5. The escalation row's SessionRef is always `instance`, even when the command names a session.
6. **The restart test is a Schedule test with a production stop and start** (`Escalations` `TestRestartRearmsOnce`, through ReconcileIn: the same `Reminder.Reconcile` that the after-start installer step calls on an IRIS start).
   - It is not a new phase of the container scripts. `live:reminder-restart` waits at least 300 s for R_future, and a local run of it cannot fit the ~150 s call bound.
   - `test-production-restart.sh` is Story 0.6/23.4's (it already pins "two Escalations after a kill page the backup once").
   - Flagged as new (see the completion summary).
7. `TestEscalationMailsTheBackup` lives in `PageRoute`, reusing its SMTP set-up (Rule 2), so the AC's "`OcuTalon.Test.Channel`, with a mock mail server" holds for the escalation's page.
8. Other paging tests in `PagingLive` (Lane A) now leave one pending escalation row per real page, due after 15 minutes, in their throwaway stack. No test asserts on it, it is torn down with the stack, and when it fires `Paging.Escalate` finds a backup already paged or the incident closed or gone. It is not cleaned, because the V5 edit is `TestEscalationAsk` only. Flagged.
9. Stale Lane A doc text is left as is: `IncidentManager.Arm`'s "(as ReminderOps gives until Story 24.3)" and the epic-24 context's "Until 24.3". Lane A owns it, and the lead re-prewarms the context.
10. **`test-readme.sh` rule `telegram-demo` exempts the one approved bullet line.** The approved On-call pages bullet is used verbatim (P4), and its sentence "When OcuTalon finds failures ... by Telegram or email, ..." mentions Telegram without the words "your own install" in that sentence (the bullet's first sentence says them). `chk_telegram_demo` skips only the line that equals `NS_ONCALL` exactly, so a changed bullet is read sentence by sentence again (a new self-test pins it). It is a shared surface that the plan did not list.
11. **A `DelaySeconds` that is not a number answers `failed`, not `bad_time`.** The command's own integer property fails its validation when the message is saved, so it never reaches ReminderOps; `TestBadFieldsRefused` pins `failed` with nothing stored. An empty, 0 and negative delay reach it and are `bad_time`.
12. **The purge part names `instance` and `escalation` as SQL literals**, not through `Schedule.Reminder`'s parameters, so that `TestOnlyOwnTablesAndAuditKept`'s scan (it allows no class call but five) still holds and needs no change.
13. **`ReminderFixture.RemoveTraces`** is the former private `Reminders.RemoveTraces`, made public with the command class as a parameter, because `Escalations`, `PageRoute` and `ReminderFixture.Remove` need it (Rule 2). `Remove` skips the Delivery and SimMessage clean-up for an instance row.
14. A repeat ask is found by `%EXACT(PageRef)`, so two Refs that differ only in case are two pages.
15. A `CancelReminder` from system for an escalation row that is not pending is `no_reminder` whatever its key (no repeat answer), as the Matrix says.
16. `Schedule.Reminder` gains the parameters `OWNER` (`instance`), `ESCALATION` and `ESCALATIONITEM` (`IncidentManager`), `SuperSessionOf` (shared by `StartWaiter`, `EndWaiter` and `StartFrom`), `Armable` and `Escalate`; `ReminderOps` gains `Escalate`, `CancelEscalation` and `IsEscalation`.
17. `Escalations` sets `onlineDemo` to "" before each test and restores the saved value after it; its live-event checks compare counts with the count at the start, because a mutated run leaves events on the instance stream of a warm stack.

### Measured (Task 0; lane-D stacks; anything not measured is labelled "(inference)")
- (a) The real `IncidentManager` `Arm` chain (IM -> `Commands.Submit` -> ReminderOps -> ReminderTimer, with the waiter start) does not deadlock. `PagingLive` `TestRealBreakPagesTelegram` (warm, 34 s, passes) made two real asks from `system`; their CommandsIn -> ReminderOps request headers (the request that holds the waiter start) were created and processed 2 ms and 3 ms apart. From the test process, `Commands.Submit` of the ask answers in 0.002 to 0.003 s warm and 0.054 s on the first call of a fresh stack (`PagingLive` `TestEscalationAsk`).
- (b) The nested cancel completes: `AckPage` from `web_user` -> IncidentManager `Followed` -> `CancelReminder` from `system` -> ReminderOps answered handled and cancelled the row, and ended the waiter, in 0.053 s warm and 0.086 s fresh (`TestBackupPagedOnceUnlessAcknowledged`).
- (c) A live ReminderTimer waiter survives `StopProduction` and `StartProduction`: C (set through the product) kept its one start header and its one waiter and fired once at its due time. `StopProduction(10, 0)` returned in under 0.1 s, `StartProduction` in 0.1 s, and ReconcileIn's Info row came 5.1 to 5.6 s after the start call (`TestRestartRearmsOnce`). The test's delay for C is 45 s so that it falls due after the start (its whole run is 45 s warm, 86 s for the class on a fresh stack).
- The warm stack's production jobs keep the class they loaded at their start, so each mutation of `ReminderOps` or `Reminder` was followed by `Reminders:TestReconcileWithoutProductionDoesNothing` (a stop and start) before its target test.

### Spine updates (V4; Rule 20; the lead applies them and reports OLD and NEW at merge; this stage does not edit the spine)
`_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md`.

**AD-18, OLD (verbatim, the sub-bullets of "Escalation timers (step 5)"):**
> - From Story 24.3, `ReminderOps` accepts an escalation only from origin `system` (the paging owner) with `DelaySeconds`. Its row has `SessionRef` `instance`, appears in no `ListReminders` and no live event, and is cancelled by `CancelReminder` from `system`.
> - At its due time the waiter (`ReminderTimer`, then `Schedule.Reminder.Wake`) sends `OcuTalon.Msg.Escalation` (`IncidentRef`, `PageRef`) to `IncidentManager` asynchronously, instead of a Notification. The reconciler re-arms it like a reminder. `Data.Reminder` appends `Kind`, `IncidentRef` and `PageRef` (Story 24.3).
> - Until Story 24.3, `ReminderOps` answers any `Kind` other than "" or `reminder` with `not_built` and stores nothing, so a timer request from Story 23.4 never becomes a user-visible reminder (Story 36.2).

**AD-18, NEW:**
> - From Story 24.3b, `ReminderOps` accepts an escalation only from origin `system` (the paging owner) with `DelaySeconds`. Its row has `SessionRef` `instance`, appears in no `ListReminders` and no live event, and is cancelled by `CancelReminder` from `system`. As built in Story 24.3b [AMENDED 2026-11-16, Story 24.3b, Contest Planner 24.3 rulings V1 and V2]:
>   - The escalation is checked before any session: any other origin, and the online demo, answer `not_allowed` and write nothing.
>   - It needs both Refs and a whole `DelaySeconds` above 0 (else `bad_time`).
>   - A page has at most one row: a repeat ask for its `PageRef` answers that row, in any state.
>   - The waiter's trace session has an empty SuperSession (no session TraceRef exists for `instance`).
> - At its due time the waiter (`ReminderTimer`, then `Schedule.Reminder.Wake`) marks the row fired under its lock, then sends `OcuTalon.Msg.Escalation` (`IncidentRef`, `PageRef`) to `IncidentManager` asynchronously, instead of a Notification, so two waiters of one row send one. The reconciler re-arms a pending escalation row whose waiter is gone like a reminder, exactly once per start (a row with a live waiter is left alone), and never skips it as sessionless. `Data.Reminder` appends `Kind`, `IncidentRef` and `PageRef` (Story 24.3b).
> - Any `Kind` other than "", `reminder` or `escalation` is answered `not_built` and stores nothing.

**AD-27, OLD (verbatim, in the `OcuTalon.Data.Purge.Run` bullet):**
> With the session go its GuideState, SimMessage, BreakFeedRun and finished Reminder rows, and its conversation links through `OcuTalon.Bridge.Purge.DropLinks`, so that the bridge's purge frees their AI sessions; memories and documents are never deleted by it.

**AD-27, NEW:**
> With the session go its GuideState, SimMessage, BreakFeedRun and finished Reminder rows, and its conversation links through `OcuTalon.Bridge.Purge.DropLinks`, so that the bridge's purge frees their AI sessions; memories and documents are never deleted by it. It also deletes the finished (fired or cancelled) escalation `Reminder` rows (`SessionRef` `instance`, AD-18) created before the cutoff; a pending one is kept [AMENDED 2026-11-16, Story 24.3b, Contest Planner 24.3 ruling V1].

Memlog: `AD-18/AD-27 amended (24.3b, V1/V2): escalation timers as built (system only, not on the demo, one row per page, fired under lock, re-armed once per start, empty SuperSession) and their purge (finished instance rows by age); prevents a restart paging the backup twice and escalation rows that never go`.

### Governing ADs (Rule 6)
- AD-1: the timer verbs through Submit, by origin.
- AD-4: session-scoped lists.
- AD-5: row truth, append-only storage, the reconciler.
- AD-13: object-access reads of the page.
- AD-15: the paging owner decides the backup.
- AD-18: escalation timers.
- AD-19: no on-call value in rows or logs.
- AD-22: mocks and throwaways.
- AD-23: reconcile at every start.
- AD-25: the online demo.
- AD-26: the waiter trace sessions.
- AD-27: purge.
- AD-29/AD-33: lanes, one writer.

### Integration ACs (Rule 1) and linkage (Rule 2)
- **Integration:** AC3. The real `IncidentManager` consumes the waiter's `Msg.Escalation` and records the backup page, and EmailOut, through Notify and the SMTP mock, delivers it. AC2's cancel is consumed from IncidentManager's `Followed`/`Unpage`.
- **Consumes:**
  - 23.4's `Arm`, `Escalated`, `Followed`, `Cancel` and `Paging.Escalate`/`Armed`;
  - 36.2's `SetReminder` fields and `Msg.Escalation`;
  - 24.3a's page route (the backup's page delivery) and `PageRoute`'s fixtures;
  - 8.x's row, waiter, reconcile and fixtures.
- **Consumed-by:** no new consumer story. Lane A's IncidentManager is the existing consumer, and the Planner's step-5 hands-on pass exercises it.

### Extend, don't copy (Rule 2)
- The escalation `Set` extends `Set`'s row, waiter and failure steps.
- `StartWaiter`, `EndWaiter`, `StartFrom` and `Reconcile` are extended for `instance` rows, never copied.
- The purge part has the shape of `DeleteTurns`.
- The tests reuse `ReminderFixture` (extended `Remove`), `Test.Data.Fixture`, `Test.Watch.Paging`, `PageRoute`'s mail helpers and `Reminders`' stop and start pattern.

### Ledger (Rule 17; `LEDGER slice 24-3b-escalate-unanswered-pages-to-the-backup-and-say-so-in-settin`)
- DW-1384 (the only entry): addressed by `PagingLive` `TestEscalationAsk` (V5), pinned by AC1's mutation.

### Files (V5/V6; the orchestrator coordinates overlaps)
- **Lane A (cross-lane, V5):** `src/ocutalon/cls/OcuTalon/Test/Watch/PagingLive.cls`: `TestEscalationAsk` and its doc lines 8 and 326, only.
- **Lane B, source:**
  - `Schedule/ReminderOps.cls`, `Schedule/Reminder.cls`, `Data/Reminder.cls`, `Data/Purge.cls`, `Msg/Command/SetReminder.cls` (doc);
  - `web/src/app/settings/settings-view.ts`, `web/src/app/settings/on-call-section.ts`.
- **Lane B, tests:**
  - `Test/Schedule/Escalations.cls` (NEW), `Test/Schedule/ReminderFixture.cls`, `Test/Schedule/Reminders.cls`;
  - `Test/Channel/PageRoute.cls`;
  - `Test/Data/Tables.cls`, `Test/Data/Purge.cls`;
  - `web/scripts/on-call-view.test.mjs`, `web/scripts/ux-strings.test.mjs`, `web/e2e/settings/on-call.spec.ts`;
  - `docker/tests/test-readme.sh`.
- **Unlisted root doc (README's companion; treated as Lane B):** `GUIDE.md`.
- **Spine (the lead):** `ARCHITECTURE-SPINE.md` and `.memlog.md`.
- **Outside epic-24's `paths_hint`** (footprint extensions to report): `Data/Purge.cls`, `Msg/Command/SetReminder.cls`, `Test/Data/{Tables,Purge}.cls`, `web/scripts/{on-call-view,ux-strings}.test.mjs`, `docker/tests/test-readme.sh`, `GUIDE.md`, and the Lane A `Test/Watch/PagingLive.cls`.

### CI
No new unit or group. `Test.Schedule.Escalations` joins `lane-b`'s `Schedule` area automatically (`ci/units.sh:21`; `test-ci-config.sh` proves it). O1 runs in `sign-in-2`.

## Public text
1. **New text 1, the On call line** (`settings-view.ts` `onCall.pages`; replaces DW-1400's line), APPROVED verbatim (Option A, 24.3 rulings):
   "OcuTalon pages the on-call person for failures it finds in the productions it watches: in their OcuTalon chat if they're an OcuTalon user, and by Telegram or email as chosen below. Email pages go out from the mailbox set up under Channels. If nobody presses Got it within the minutes below, OcuTalon pages the backup. A practice Break the feed pages nobody while its user stays signed in."
2. **The GUIDE.md bullet** (P4), APPROVED as written:
   "- **On-call pages.** On your own install, choose an on-call person and a backup in Settings > On call. When OcuTalon finds failures in a production it watches, it pages the on-call person in their OcuTalon chat and by Telegram or email, and pages the backup if nobody presses Got it in time. The online demo never pages anyone."
3. Used unchanged: `CommandsIn.MESSAGENOTALLOWED` and `MESSAGENOTBUILT`, and ReminderOps' `MESSAGESET`, `MESSAGECANCELLED` and `MESSAGEBADTIME`/`MESSAGENOREMINDER`. All are model-facing and never shown.

## Veto items
All were approved at the 24.3 gate, with the conditions pinned under Verification.
- **V1. Stored data:**
  - `Data.Reminder` appends `Kind`, `IncidentRef` and `PageRef`;
  - escalation rows are owned by `instance`;
  - the purge part removes finished rows by age;
  - nothing is written on the demo.
- **V4. AD-18 and AD-27 amendments:** OLD/NEW above.
- **V5. Cross-lane edit:** `PagingLive` `TestEscalationAsk` (DW-1384).
- **V6. Footprint extensions:** the files above.
- **V7. Public text:** the two approved texts.
- None: a new verb, route, table, index, catalog key, production item, privilege, CI unit or web dependency.

## Verification

Every `ci/iris.sh`/`ci/warm.sh` call runs from the worktree root with:

```
OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-d" OCUTALON_TEST_WEB_PORT=52804 OCUTALON_LOCK_OWNER='epic=24 stage=implement'
```

- The warm tag is `e24s3biw` and the fresh tag is `e24s3bi`. IRIS MCP calls go to `ocutalon-slot-d`/`OCUTALON` only.
- Each line is one foreground call (`timeout: 600000`) that ends inside about 150 s. Run one class, or one `Class:Method`, per call, and never two test calls in one message.
- A production job keeps the class it loaded at its start, so record evidence for `Escalations`, `PageRoute` and `PagingLive` on a fresh stack.
- After a `web/` change, run `ci/iris.sh build` before a browser part.

**Shared surfaces:**
- The Reminder contract and its readers: `Test.Data.Tables`, `Test.Data.Ownership`, `Test.Data.Purge` (`TestOnlyOwnTablesAndAuditKept`), `docker/tests/test-storage.sh`.
- The escalation `not_built` pins, replaced: `Test.Schedule.Reminders` 668-771 and `Test.Watch.PagingLive` `TestEscalationAsk`.
- Every test that counts all Reminder rows or calls `Reconcile` with no list:
  - `Test.Demo.GuidePrompts:234` and `Test.Tools.Reminders:1283` (`COUNT(*)`);
  - `Test.Install.Registry:426` (the Schedule step's `Reconcile()`).
  - An `instance` row is now re-armed, not skipped. Search the test trees for `OcuTalon_Data.Reminder` and `Reconcile(`.
- Real pages now create escalation rows: `PagingLive`, and `PageRoute` where it pages through IncidentManager (Decided 8).
- The On call texts: `ux-strings`, `on-call-view`, O1.
- GUIDE's `New since 1.0.0` list: `test-readme.sh` `new-since`.

Standing criterion: every test added or changed passes on a fresh environment, in either order.

**Commands:**
- (loop) `npm --prefix web test` -- passes.
- (once) `npm --prefix web run lint` and `npm --prefix web run build` -- pass, with no budget error.
- (once) `bash docker/tests/test-readme.sh`, `bash docker/tests/test-class-rules.sh`, `bash docker/tests/test-storage.sh`, `bash docker/tests/test-ci-config.sh` -- each passes, one per call.
- (once) `… OCUTALON_RUN_TAG=e24s3biw ci/warm.sh up` -- ready.
- (loop) `… OCUTALON_WARM=1 OCUTALON_RUN_TAG=e24s3biw ci/iris.sh class <Class>`, one call each:
  - `OcuTalon.Test.Data.Tables`, `OcuTalon.Test.Data.Purge`;
  - `OcuTalon.Test.Schedule.Reminders`;
  - `OcuTalon.Test.Schedule.Escalations:<Method>`.
  - Each gives `CLASS … passed`.
- (once) `… OCUTALON_RUN_TAG=e24s3biw ci/warm.sh down`.
- (once, each its own call) `… OCUTALON_RUN_TAG=e24s3bi ci/iris.sh class` for:
  - `OcuTalon.Test.Schedule.Escalations` (split by `:Method` if it nears 150 s);
  - `OcuTalon.Test.Channel.PageRoute:TestEscalationMailsTheBackup`;
  - `OcuTalon.Test.Watch.PagingLive:TestEscalationAsk`;
  - `OcuTalon.Test.Schedule.Reminders`.
  - Each passes on a fresh stack.
- (once) `… OCUTALON_RUN_TAG=e24s3bi ci/iris.sh build`. Then (loop) `… ci/iris.sh live sign-in-2 --part k/N` for the part holding `settings/on-call.spec.ts` (`web/scripts/e2e-part.mjs` lists the parts). Choose N so each part ends inside about 150 s.
- The lead's fresh-environment check (Rule 19) runs the shards forward and in reverse as usual.

**Mutations (Rule 19; one per AC and per ruled condition; the implement stage records each observed red, reverts, and checks that `cmp`/`git diff --stat` are unchanged):**
- AC1 (waiter): the escalation `Set` saves the row but does not start the waiter → `Escalations` `TestAskMakesOneInstanceRow` (no live waiter).
- AC1 / DW-1384: restore `Set`'s `not_built` guard for `escalation` → `PagingLive` `TestEscalationAsk`.
- AC1 / origin: drop the `system` origin check → `TestOnlySystemMayAsk`.
- V2 (one escalation per page): drop the PageRef lookup → `TestAskAgainSameRow` (two rows).
- V1c (nothing on the demo): drop the online-demo check → `TestOnlineDemoWritesNothing` (a row exists).
- AC2 (escalation, not a notification): `Wake` sends the reminder Notification for an escalation row → `TestDueSendsOneEscalation` (no Escalation header; a Notify request).
- V1c (never pages twice): skip `Wake`'s pending check for escalation rows → `TestDueSendsOneEscalation` (two Escalations from two waiters).
- AC2 (cancel): the system branch of `Cancel` removed (the session path answers) → `TestCancelFromSystem` (`no_reminder`, the row stays pending).
- AC2 (the waiter ends at once): the system branch skips `EndWaiter` → `TestCancelFromSystem` (the waiter still waits).
- AC3 (Integration): `Wake` sends the Escalation to `Notify` instead of `IncidentManager` → `TestBackupPagedOnceUnlessAcknowledged` and `PageRoute` `TestEscalationMailsTheBackup` (no backup page, no mail).
- AC4 / V1c (survives a restart): `Reconcile` skips `instance` rows as sessionless → `TestRestartRearmsOnce` (the lost rows never fire or wait).
- V1c (re-armed exactly once): drop `Reconcile`'s `LiveWaiter` skip → `TestRestartRearmsOnce` (the second Reconcile adds a start header).
- AC5 (no list): store the command's SessionRef on the row when it is given → `TestNotInAnyList` (the row is in the session's ListReminders).
- AC5 (ids only): `Wake` logs the page's Person (`Data.Page`) in an Info line → `PageRoute` `TestEscalationMailsTheBackup` (the address is in the log; positive control: the mock's mail).
- AC6 / V1c (finished only): drop the `State IN ('fired','cancelled')` filter → `TestFinishedEscalationsGo` (the pending row is gone). Drop `SessionRef = 'instance'` → the kept session's finished reminder is gone.
- AC6 / V1c (purging removes them): do not call `DeleteEscalations` from `Run` → `TestFinishedEscalationsGo` (old finished rows stay).
- AC7: restore DW-1400's line in `settings-view.ts` → `on-call-view.test.mjs` and `ux-strings.test.mjs` red, and O1 red.
- AC8: write the bullet with `Settings › On call` → `test-readme.sh` `new-since` (`NS_ONCALL`). Removing the bullet → "missing 'B On-call pages'".

**Mutations run (Rule 19; implement stage; each applied on the warm lane-D stack (after a production restart where a production job runs the changed class), observed red, reverted from a copy saved before it, `cmp` identical, `git status --short` and `git diff --stat` identical to before):**
- mutation: AC1 (waiter), the escalation `Set` saves the row but does not start the waiter -> `Escalations` `TestAskMakesOneInstanceRow` red (no header id, no ReminderTimer, no start header).
- mutation: AC1 / DW-1384, `Set`'s `not_built` guard restored for `escalation` -> `PagingLive` `TestEscalationAsk` red (Ok 0 not_built, no row).
- mutation: AC1 (origin), the `system` origin check dropped -> `Escalations` `TestOnlySystemMayAsk` red (web_user, web_admin, telegram, timer and tool are set).
- mutation: V2 (one escalation per page), the PageRef lookup dropped -> `TestAskAgainSameRow` red (a second row and waiter).
- mutation: V1c (nothing on the demo), the online-demo check dropped -> `TestOnlineDemoWritesNothing` red (a row, a ReminderStart and a ReminderTimer exist).
- mutation: AC2 (an Escalation, not a Notification), `Wake`'s escalation branch removed so the reminder Notification goes -> `TestDueSendsOneEscalation` red (no Escalation header, a Notify request, an event).
- mutation: V1c (never pages twice), `Wake`'s pending check skipped for escalation rows -> `TestDueSendsOneEscalation` red (two Escalations from two waiters).
- mutation: AC2 (cancel), the system branch of `Cancel` removed -> `TestCancelFromSystem` red (no_session, the row stays pending, the waiter keeps waiting).
- mutation: AC2 (the waiter ends at once), the system branch skips `EndWaiter` -> `TestCancelFromSystem` red (the waiter still waits).
- mutation: AC3 (Integration), `ESCALATIONITEM` is `Notify` instead of `IncidentManager` -> `TestBackupPagedOnceUnlessAcknowledged` red (no backup page row) and `PageRoute` `TestEscalationMailsTheBackup` red (no backup page row, no mail).
- mutation: AC4 / V1c (survives a restart), `Armable` no longer accepts instance rows (they are skipped as sessionless) -> `TestRestartRearmsOnce` red (A never fires, B never waits).
- mutation: V1c (re-armed exactly once), `Reconcile`'s `LiveWaiter` skip dropped -> `TestRestartRearmsOnce` red (the second Reconcile adds a start header, C has two waiters).
- mutation: AC5 (no list), the command's SessionRef stored on the row when given -> `TestNotInAnyList` red (the row is in the session's list and readers).
- mutation: AC5 (ids only), `Escalate` logs the page's Person (`Data.Page`) in an Info line -> `PageRoute` `TestEscalationMailsTheBackup` red (the address is in the log; the mock's mail is the positive control).
- mutation: AC6 / V1c (finished only), the `State IN ('fired','cancelled')` filter dropped -> `Test.Data.Purge` `TestFinishedEscalationsGo` red (the pending row is gone).
- mutation: AC6 / V1c, `SessionRef = 'instance'` dropped -> `TestFinishedEscalationsGo` red (the kept session's finished row of Kind escalation is gone).
- mutation: AC6 / V1c, `Kind = 'escalation'` dropped -> `TestFinishedEscalationsGo` red (the finished row of Kind empty that instance owns is gone).
- mutation: AC6 / V1c (purging removes them), `DeleteEscalations` not called from `Run` -> `TestFinishedEscalationsGo` red (old finished rows stay, also through `Retention.Purge`).
- mutation: AC7 / the On call line, `settings-view.ts` restored to DW-1400's line -> `on-call-view.test.mjs` ("are shown byte for byte") red, `ux-strings.test.mjs` red (two entries: "has an entry for every inventory string" and "has no entry that matches no inventory string"), and `live sign-in-2 --part 10/12` O1 red (the pages line is not visible); on the unmutated tree the same part passes 16 of 16.
- mutation: AC8 / the GUIDE bullet (owner-pinned), `Settings > On call` written as `Settings` U+203A `On call` -> `test-readme.sh` `new-since` red ("the guide does not hold the approved bullet 'On-call pages' once, word for word"; `telegram-demo` red too, because the changed line is no longer the exempt one).
- mutation: AC8, the bullet removed -> `new-since` red ("missing 'B On-call pages'").
- mutation: AC1 (a failed start), the `%DeleteId` of `ReminderOps.Escalate`'s failed-start branch removed -> `ReminderLogic` `TestEscalationStartFailureKeepsNothing` red ("no row names the page").
- mutation: AC2 (a failed send is logged), the `$$$LOGERROR` of `Reminder.Escalate` removed -> `ReminderLogic` `TestWakeEscalationSendFails` red ("one error is logged with the Ref").
- mutation: AC2 (a busy lock), the lock-failed branch of `CancelEscalation` disabled -> `ReminderLogic` `TestCancelEscalationBusyRowFails` red (the cancel does not answer failed, no warning).
- mutation: AC3 (acknowledged first), `CancelEscalation` answers no_reminder without cancelling -> `Escalations` `TestBackupPagedOnceUnlessAcknowledged` red (case B: the row is not cancelled, the waiter does not end, an Escalation was sent).

**Verified (implement stage, lane D):**
- Warm (`e24s3biw`): `Test.Data.Tables`, `Test.Data.Purge`, `Test.Schedule.Reminders` (83 s), each `Escalations` method one by one, `PageRoute:TestEscalationMailsTheBackup`, `PagingLive:TestEscalationAsk` and `:TestRealBreakPagesTelegram`, and the shared surfaces `Test.Data.Ownership`, `Test.Install.Registry`, `Test.Tools.Reminders`, `Test.Demo.GuidePrompts`, `Test.Schedule.ReminderLogic`, `Test.Schedule.ReminderChat` and `Test.Bridge.CodeRules` passed.
- Fresh (`e24s3bi`): `Test.Schedule.Escalations` (86 s of tests, 217 s with the stack), `PageRoute:TestEscalationMailsTheBackup` (23 s), `PagingLive:TestEscalationAsk` and `Test.Schedule.Reminders` (84 s) passed; `ci/iris.sh build`, then `live sign-in-2 --part 10/12` (`settings/on-call.spec.ts`, O1 to O16) passed 16 of 16 in 12 s of tests.
- `npm --prefix web test` (2188 pass), `npm --prefix web run lint`, `npm --prefix web run build` (the one existing `demo-guide.ts` style budget warning, no error), `bash docker/tests/test-readme.sh`, `test-class-rules.sh`, `test-storage.sh` and `test-ci-config.sh` pass. Both stacks were torn down.

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** An unanswered page now reaches the backup. `ReminderOps` takes the paging owner's escalation ask (origin `system`, never on the online demo, one row per page, owner `instance`, empty SuperSession waiter), `Reminder.Wake` marks the row fired under its lock and sends one `Msg.Escalation` to `IncidentManager` (no Notification, no event), `CancelReminder` from `system` cancels it and ends its waiter, `Reconcile` re-arms a lost waiter exactly once, `Data.Purge` deletes only finished `instance` escalation rows, Settings shows the approved On call line, GUIDE has the approved bullet, and DW-1384's `TestEscalationAsk` asserts the real ask.

**Files changed.**
- Lane B source: `src/ocutalon/cls/OcuTalon/Schedule/ReminderOps.cls`, `Schedule/Reminder.cls` (escalation path, due, cancel, re-arm), `Data/Reminder.cls` (Kind, IncidentRef, PageRef; storage 12-14), `Data/Purge.cls` (`DeleteEscalations`), `Msg/Command/SetReminder.cls` (doc), `web/src/app/settings/settings-view.ts` and `on-call-section.ts` (the `pages` line, id `oncall-pages`), `GUIDE.md` (the On-call pages bullet).
- Lane B tests: `Test/Schedule/Escalations.cls` (new), `ReminderFixture.cls`, `Reminders.cls`, `ReminderLogic.cls`, `ReminderTimerDouble.cls`, `Test/Channel/PageRoute.cls`, `Test/Data/Tables.cls`, `Test/Data/Purge.cls`, `web/scripts/on-call-view.test.mjs`, `web/scripts/ux-strings.test.mjs`, `web/e2e/settings/on-call.spec.ts`, `docker/tests/test-readme.sh`.
- Lane A (V5, DW-1384): `src/ocutalon/cls/OcuTalon/Test/Watch/PagingLive.cls`, `TestEscalationAsk` and its doc lines only.

**Review findings.** 29 findings, 0 high. Patched: 1 medium entry (untested failure paths: three `ReminderLogic` tests) and 7 low (Purge doc, `%SQLCODE` guard, Escalate doc, `$IsObject` guard, a conditional assertion, a refusal Message, the acknowledged-first mutation). Deferred: none. Rejected with their reasons: see the Review Triage Log.

**Follow-up review recommended:** false (no high patched; one medium entry patched).

**Verification.** `npm --prefix web test` 2188 pass; web lint and build pass; `test-readme.sh`, `test-class-rules.sh`, `test-storage.sh`, `test-ci-config.sh` pass. On lane D: warm `ReminderLogic` passed (with its three new tests) and fresh `ReminderLogic` passed; fresh `Escalations` passed (86 s of tests); fresh `PageRoute:TestEscalationMailsTheBackup` passed; the implement stage's runs of `Tables`, `Purge`, `Reminders`, `PagingLive:TestEscalationAsk` and `live sign-in-2` (O1 to O16) passed. Every mutation line under Verification was observed red and reverted `cmp`-identical, the four added in review included.

**Residual risks.**
- Other `PagingLive` tests leave one pending escalation row per real page in their throwaway stack (Decided 8).
- A crash between marking the row fired and sending the Escalation loses that page's backup page (spec-bound: never twice).
- The spine's AD-18 and AD-27 text is amended by the lead at merge (Design Notes > Spine updates); `ARCHITECTURE-SPINE.md` is unchanged here.
- `_bmad-output/implementation-artifacts/deferred-work.md` was modified in the worktree by the epic runner during this run (one ledger trailer line, not this story's); it is not part of this story's commit.
