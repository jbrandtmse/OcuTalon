# Epic 5 Context: OcuTalon watches a production and explains what broke

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Epic 5 (Lane A) builds OcuTalon's IRIS watch, the middle of the demo between "watch the Orders production" and "approve the fix". A user asks in plain words to watch a production, or to stop. New failures are picked up within seconds, and same-cause failures become one incident by the settle rule. The Diagnosis agent then explains the incident from the failed messages: a plain-English cause, the element at fault and a proposed fix, with the evidence behind Show details. Each incident moves through a fixed state table and closes. The heartbeat runs every watch's check, and "is everything fine?" is answered from results computed by code, so OcuTalon never gives a false all-clear. Epic 6 (incident cards) and Epic 7 (dry run, approval and fix) build on this epic.

## Stories

- Story 5.1: Ask OcuTalon to watch a production, and to stop
- Story 5.2: New failures are picked up within seconds
- Story 5.3: Same-cause failures become one incident by the settle rule
- Story 5.4: The diagnosis explains the cause from the failed messages
- Story 5.5: An incident moves through its states and closes
- Story 5.6: The production watch runs on every heartbeat
- Story 5.7: Asked whether everything is fine, OcuTalon never gives a false all-clear

## Requirements & Constraints

- **Watching:** needs no configuration.
  - A production is matched by display name in any namespace whose data database the service user may read.
  - For an unknown name, OcuTalon creates nothing, lists the productions it can see and asks which was meant.
  - The online demo watches only Orders.
  - Stopping removes that session's watch only.
  - A cleanly stopped production is still watchable, and a watch can always be stopped from chat.
- **Reacting:**
  - Pickup takes at most 15 s, typically under 3 s.
  - It works on any production without changing it or relying on its alerts.
  - No failure is skipped or counted twice, including across restarts.
  - Each poll sends one batch per production and scope, and only when something is new.
  - Namespaces the service user can't read are never read.
- **Settle rule:** the notice step starts after 10 s with no new same-cause failure, or 30 s after the first failure, whichever comes first. Both values come from settings.
  - A burst of 50 gives one incident with `NoticeCount` 50.
  - A trickle gives one incident 30 s after its first failure.
  - Later same-cause failures update `Count` only, never giving a second incident or notice.
- **Scope:** a session-tagged failure stays that session's. Untagged (`instance`) failures give one incident per cause, shared by every session watching that production, with one notice per watcher session.
- **Notices:** a typical diagnosis needs one model request. Each notice is one of three variants:
  - **with a fix:** a data-format cause. Story 7.2 adds the dry run and the approval;
  - **no fix:** any other cause, `unknown` included, with no `ApprovalRef`;
  - **fallback:** fixed grouping by production item plus error pattern, flagged, with no cause and no fix.
- **Time budget:** at most 60 s from Break the feed to the notice in 19 of 20 runs, about 30–35 s typical. It is measured in the clean-machine rehearsal, never in CI.
- **Closing:**
  - A resolved incident closes after 15 quiet minutes, on Dismiss, or for a replay.
  - An open incident (fallback, no fix, rejected or expired) closes on Dismiss, and after 15 quiet minutes only with demo mode off.
  - An incident awaiting approval or fixing never closes this way.
  - Only a recipient session may dismiss.
  - A same-cause failure after closing opens a new incident.
- **No false all-clear:** code alone decides it. With Orders failing, "is everything OK?" gets no all-clear, even when the mock model claims everything is fine.
- **Retention:** incidents closed longer ago than `daysToKeep` (default 90) are deleted with their failure groups.
- **Plain English:** class names, error codes and class paths appear only behind Show details.

## Technical Decisions

- **Ownership (Lane A):**
  - production items `FailurePoller`, `IncidentManager` and `WatchOps` (`OcuTalon.Watch.FailurePoller`, `.IncidentManager`, `.Ops`) and `Checks` (`OcuTalon.Checks.Process`);
  - tables `BackgroundCheck`, `WatchMark`, `Incident` and `FailureGroup`. `WatchOps` alone writes watch rows, `FailurePoller` alone writes `WatchMark`, and `IncidentManager` alone writes incidents and groups and publishes `incident` and `watch.progress`. `Checks` alone publishes `check`, including when a watch starts or stops.

  Catalog keys go in `OcuTalon.Msg.Catalog.Watch`, mock scenarios in `ci/mock/scenarios/A/`, and edits to the production class only in Lane A's region. Lane B owns `Session`, `Ownership`, `Live`, `Msg`, `Core`, `Setting` and `Schedule`: ask, don't edit.
- **Commands (AD-1):** state-changing tools submit `OcuTalon.Msg.Command` verbs through `OcuTalon.Tools.CommandCall.Run`, which goes through `Commands.Submit` with origin `tool` and an `IdempotencyKey` of `ItemId:position`. They return the owner's synchronous `CommandResult`, never write tables, and are tested against the `CommandsIn` double. Owners ignore repeats.
- **Tools:**
  - **Declaration:** each tool declares `CLASSIFICATION`, `READONLY`, `TRUSTEDOUTPUT`, `STEPLABEL` and `RESOURCES` as parameters suffixed with the tool name, and returns only through `Return` (`OcuTalon.Tools.Result`) as a dynamic object or text.
  - **The gate:** in an untrusted or tainted turn it runs only safe, read-only calls, and allowing a tool that isn't trusted output taints the turn.
  - **Classifications:**
    - `start_watch`, `stop_watch` and dismiss are safe but not read-only;
    - `list_productions` and `check_status` are read-only;
    - the three watch tools and `check_status` are trusted output, built by code from OcuTalon's records and the instance's production registry;
    - Diagnosis's toolset `OcuTalon.Tools.Watch` is read-only and never trusted. The Chat agent's toolset is `OcuTalon.Tools.Watching`.
  - **Callback safety:** tools run inside AI Hub callbacks, so they make no `%AI` native calls, run no Python and make no session calls. Every class they call there must be in `CodeRules.CALLBACKHELPERS`.
- **Reading IRIS (AD-3):**
  - Only `OcuTalon.Watch.Reader` switches namespace, in one `New $NAMESPACE` method that calls no OcuTalon class while switched.
  - A namespace is readable when `$SYSTEM.Security.CheckUserPermission` gives the service user Read on its data database, checked before any switch.
  - A production is read only while it is its namespace's own: the running one, else the last active one (`Ens.Director.GetActiveProductionName()`), never another `Ens.Config.Production` row (DW-38, DW-222).
  - With demo mode on, the Demo step gives `OcuTalonServiceRole` Read on `%DB_OCUORDERS_DATA` only (no code database, SQL or write), and the off and keep paths remove it. That grant is what lets an install find Orders.
- **Watch failures (AD-15):**
  - A failure is a message header in `Status` 8 (Error), whatever its `IsError` (build 154 leaves it 0), or an event-log row of `Type` 2 (Error) or 6 (Alert) with no `SessionId`. A log row with a session only gives its header's error text.
  - Error text enters OcuTalon's messages redacted: `OcuTalon.Watch.ErrorText.Sentence` takes the error's own sentence out of the "Terminating BP" wrapper after `OcuTalon.Bridge.Redact`.
  - `FailurePoller` reads from a time-based mark on `WatchMark`: `MarkAt` (the newest failure time read) and `Seen` (the failures already batched within a 2-second overlap before it), starting no earlier than the earliest watch's `BackgroundCheck.CreatedAt`. A production the reader does not read keeps its mark.
  - Each poll sends `IncidentManager` one `FailureBatch` per production and scope (at most 500 failures), each its own trace session with the scope's `TraceRef` as `SuperSession`, then saves the mark. Send and save can't share a transaction, so a crash between them re-sends that poll once and never skips; `IncidentManager` ignores a failure it already holds (`h<HeaderId>` or `l<LogId>`).
  - **Same cause** is the same namespace, production, scope, item and error pattern (the error text with each run of digits masked), compared exactly. A failure joins the newest incident of its cause that is not `closed`. `FailureGroup.Seen` holds the keys of the group's newest 1000 failures (two polls' worth).
  - The settle values are the settings `watch.settleQuietSeconds` (default 10) and `watch.settleMaxSeconds` (default 30), read through `Data.Setting`. No setting rows are seeded until the settings page exists.
- **Scope (AD-4):**
  - A failure belongs to the session whose `TraceRef` is the message's `SuperSession`, otherwise to `instance`.
  - A failure of a copy a fix registered is the fix's, never a group's.
  - `OcuTalon.Data.Session.Recipients(ownerRef, incidentRef)` resolves an incident's sessions. A failed read never means "nobody watches" (DW-68).
- **Incident lifecycle (AD-15):**
  - `Ref` is set at the first failure. `IncidentManager` runs as one job (`PoolSize` 1), which serializes batches, settle wakes and, later, commands.
  - Before the notice, only `watch.progress` goes out (`noticed`, `settling`, `diagnosing`), keyed by `Ref`, with no counts and no `incident` event.
  - One waiter per new group (an `IncidentManager` instance started by a self-sent `Watch.Msg.Settle`) waits on the settle rule and re-reads the rows on each wake. Settle state lives only in rows and the persisted instance with its alarm (AD-5), and no alarm is longer than 120 s.
  - The rule reads the failures' own times (`FirstAt`, `LastAt` from `FailedAt`), so the notice's start time and the 15-minute quiet close do too. `NoticeCount` is fixed once at the settle end; `Count` keeps moving.
  - `NoticedAt` (UTC) is set only at the notice, and the ownership API hides the incident until then.
  - Others reach `IncidentManager` only through `IncidentCommand` (`dismiss`, `closeForReplay` and `closeQuiet`, all synchronous), `ApprovalOutcome` and `FixResult`.

  One transition table governs every move, with the states from `OcuTalon.Msg.Enum` and the open variant (`fallback`, `no_fix`, `rejected`, `expired`) stored beside the state:
  - while a fix runs, the state is `fixing`; otherwise `awaiting_approval` while any request is pending; otherwise the outcome that arrived last;
  - one fix runs at a time per incident;
  - a cancelled request sends no `ApprovalOutcome`.

  Its unit test covers every row and every refused move. Story 5.5 creates `OcuTalon.Fix.Msg.Execute` and `.FixResult`.
- **Diagnosis (AD-6/8/26/30):**
  - It runs in the incident's own trace session (`TraceHeaderId`), which the settle waiter started with `%SessionId` cleared, keeping the `SuperSession`.
  - `OcuTalon.Watch.EvidencePack.Build(source)` builds the pack from the live reader or a recorded snapshot, with credential values removed, and sends it as a `diagnose` request through `Decide`. The result never goes to `OutcomeRouter`.
  - The reply is checked against `OcuTalon.Watch.Msg.DiagnosisPayload`; a reply that fails is `invalid`. Only the bridge classifies fallbacks.
  - When no usable noun comes back, code takes it from `OcuTalon.Watch.ItemNoun` ("order"/"orders" for the Orders class, otherwise "message"/"messages").
  - A fallback error summary is the error's first sentence, at most 80 characters, through `OcuTalon.Bridge.Redact`.
- **Notices and live payload (AD-12/32):**
  - Each recipient session gets one `OcuTalon.Msg.Notification` of kind `incident`, with a catalog key and `Slots`: integer counts, UTC ISO 8601 times, `itemNoun: {"one","other"}`, and model sentences without times.
  - Producers never render; render tests use `OcuTalon.Msg.Catalog.Render`.
  - Each `incident` event carries the full current view (`OcuTalon.Live.Payload.Incident.FromRow`, including `CauseCategory`, `Element`, `Evidence`, `Groups`, `Requests` and `TraceTargets`). It is published through `OcuTalon.Live.Publish` after commit, never inside an open transaction.
- **Checks (AD-18/28):**
  - A `Tick` runs each due `BackgroundCheck` once, even after several missed runs.
  - Each run records the last run, a result (`passed`, `failed` with the finding, or `not_checked` with the reason), the time and its trace header id.
  - A production watch checks the running state, new errors, the open incident and the latest run time through the reader, and a reader error gives `not_checked`.
  - `Checks` sends `closeQuiet` for incidents whose last failure is more than 15 minutes old.
  - No finding becomes an Item here; that is Story 30.4.
- **All-clear (AD-28/31):**
  - `OcuTalon.Checks.Render(results, *rows)` returns a catalog key and code-computed rows `{result, entry, finding, checkedAt}`.
  - `check_status` puts the results in `HostData.checks`, which `Conversation` (Lane B) passes to `Render` unread and attaches after the guard.
  - `OcuTalon.Checks.ReplyGuard` extends `OcuTalon.Bridge.Ext.ReplyFilter` in place of Epic 0's stub. It runs exactly once on model text before the text leaves `Decide`, removes the reserved sentences and the banned phrases, and keeps the rest.
- **Conventions:** times are stored as UTC and converted only by `OcuTalon.Data.Time`. Tests call the Watch area's `Purge(daysToKeep)` directly until Story 30.2's task exists.

## UX & Interaction Patterns

- **Watch replies** are in the Chat agent's instructions: "I'll watch the {production} production and stay quiet unless something needs you.", plus the catalog's `watch.unknownProduction` and `watch.onlyOrders` texts.
- **Background-check row:** the name ("Orders production"), the schedule ("Live, plus a check every minute"), the last run, the result and a trace link to the latest run.
- **Before the notice:** there is no incident card, only Break the feed's progress lines driven by `watch.progress`, without counts:
  - "OcuTalon noticed failures in the Orders production"
  - "Waiting for the failures to settle"
  - "Working out the cause from the failed messages"
- **Notices:** numbers first, then the cause, then the choice. The no-fix and fallback texts are fixed in the catalog and say "Nothing was changed." Each fallback "Failures:" line gives the item, the count, the error summary in single quotes and the first time.
- **Show details** needs:
  - the cause category and the element;
  - a sample failed message with its error;
  - failures per item with their first and last times;
  - trace links to the sample and the first failure.

  The incident's own trace link opens the diagnosis session.
- **Reserved sentences:**
  - "Everything I checked passed." appears only when every check passed.
  - Otherwise the failing entry comes first ("Not everything: {what failed, with its time}."), then "Everything else I checked passed." only if other checks passed.
  - With nothing watched: "I'm not watching any productions yet, so I can't say. Ask me to watch one."

  The guard always removes "all good", "everything's fine", "everything is fine", "no issues", "no problems" and "nothing to worry about".

## Cross-Story Dependencies

- **Built by 5.1 (done), to reuse rather than duplicate:**
  - `Watch.Reader` (`Productions`, `Find`, `Admits`), which 5.4's evidence and toolset and 5.6's checks read through;
  - the real `WatchOps`: rows of `Kind` `production`, a `NextDueAt` of the creation time (so the first `Tick` runs the check) and an empty `Result`;
  - `Tools.WatchTools`, `Tools.WatchAnswers`, `Tools.Watching` and the generalised `CommandCall`, which 5.5's dismiss tool and 5.7's `check_status` follow;
  - the Demo step's service-role grant.
- **Built by 5.2 (done), to reuse rather than duplicate:**
  - `FailurePoller` (every 3 s) and its contract `Watch.Msg.FailureBatch` of `Watch.Msg.Failure` items;
  - `Watch.Mark` (the mark rules and the failure key) and `Watch.ErrorText.Sentence`, which 5.4's evidence and 6.1's fallback "Failures:" line reuse;
  - `Reader.Failures` (`read`, `unreadable` or `not_current`), which 5.4's evidence pack and 5.6's new-errors check read through; the stopped-production listing, whose state 5.6 reports; the name matcher `Reader.Matches`;
  - `BackgroundCheck.CreatedAt` and the stop resolver `WatchAnswers.ResolveStop`, which reads the session's own watches through `Ownership.Checks` before the reader.
- **Built by 5.3 (done), to reuse rather than duplicate:**
  - the real `IncidentManager` for `FailureBatch` and `Settle`: incidents and groups, `noticed` and `settling` to each `Session.Recipients` session (its `Tell` logs one Type 3 warning per failed event and leaves the rows standing), one `incident` event per batch that adds failures to a noticed incident, and the waiter, which sets `TraceHeaderId`, fixes `NoticeCount` and leaves `NoticedAt` empty;
  - `Watch.Settle` (`Pattern`, `Values`, `Wait`, `Alarm`, `Hold`), `Watch.Msg.Settle`, `Mark.KeyOf` (the failure key from its parts) and `FailureGroup.Seen`;
  - `CodeRules.TestOnlyIncidentManagerWritesIncidents`, which fails if any other product class creates or deletes `Incident` or `FailureGroup` rows or publishes `incident` or `watch.progress`;
  - `Test.Watch.Case` helpers: `SendBatch` (a direct batch with the scope's `TraceRef`), `Incidents`, `Group`, `WaitIncident`, `WaitNoticeCount`, `Notice(ref)` (a fixture notice standing in for 5.4's), `Notifications(ref)`, and a cleanup of the run's incidents and groups;
  - `ci/iris.sh shard <name> --part k/n` (DW-227).

  `IncidentManager` keeps `STUB` and answers 5003 to anything else. Dropping `STUB` (5.5's commands) changes `Test.Install.Production`'s stub oracle and Epic 4's `CommandsInProduction` row that expects `Dismiss` to answer `not_built`. DW-241 stays open: `Tell`'s failed-`Recipients` branch has no test (a private `Recipients` seam would close it).
- **Within the epic:**
  - 5.1's rows feed 5.2 and 5.6, and 5.2's batches feed 5.3;
  - 5.3 ends at the settle rule. 5.4 starts at the settle end and diagnoses in the incident's session from `NoticeCount`, `TraceHeaderId` and the group's item and pattern. It owns the whole notice: the three variants, `NoticedAt`, and one `Notification` per `Session.Recipients` session with the `incident` event on each watcher's stream, several watchers of an `instance` incident included (moved from 5.3, veto U-86);
  - 5.5's table governs the moves in 5.3, 5.4 and 5.6. 5.3's lookup skips `closed` incidents, so a failure after closing opens a new one; `closeQuiet` reads `LastAt`;
  - 5.6 reads the open incident and `LastAt`, publishes the `check` event for watch starts and stops (5.1 publishes none) and feeds 5.7.
- **Merged:**
  - Epic 0: contracts, `Commands.Submit`, the renderer, Orders in OCUORDERS and the recorded snapshot;
  - Epic 1: `Decide`, the `DiagnosisAgent` runner, and the `OcuTalon.Tools.Watch` fixture that 5.4 replaces;
  - Epic 2: `Session.Recipients`, the `NoticedAt` filter, `Live.Publish`, `BridgeSink`, `Ownership.Checks` (the rail's read of watches) and `Conversation` calling `Render`;
  - Epic 3: the gate, the Approval API and `ApprovalOutcome`.
- **Not merged, so tests use fixtures or direct calls:**
  - Epic 4's Break the feed: fixtures add failing Orders messages tagged with a test session's `TraceRef`;
  - Epic 8's `HeartbeatIn`: tests send `Tick` directly;
  - Epic 7's fix-copy registry (7.3, 7.4): until then every failure is batched by scope, with the `HeaderId` and `Namespace` that 7.4's match needs;
  - Epics 6, 7 and 11, and Stories 30.2 (purge task) and 30.4 (findings);
  - Epic 9's evaluation runs will drive `WatchOps`, `IncidentManager` and `EvidencePack` with owner `eval`.
- **Later consumers:**
  - `SessionOps.End` stops a session's watches through `WatchOps` (16.4; the real path in 31.3);
  - steps 4 and 5 add `BackgroundCheck` kinds;
  - 7.2: post-notice same-cause failures that no request covers form a later group in the same incident (5.3 keeps one group per incident);
  - 7.3: a group's full message list comes through the reader or an extended group, since `Seen` keeps only the newest 1000 keys.
- **Shared files:**
  - `Install/Step/Demo.cls` and `Test/Core/CommandsInProduction.cls` are Epic 4's. 5.1 edited them by ruling, so Epic 4 merges forward as a plain union, and DW-223 folds `WithOrdersData` into `WithOrders` after Epic 4 merges.
  - `Test/Data/Tables.cls` (Epic 16's) pins table property sets in its Contracts XData. A standing ruling lets Epic 5 change only the entries of Lane A's own tables (`BackgroundCheck`, `WatchMark`, `Incident`, `FailureGroup`, `FixRun`), a plain union at merge-forward; any other change there needs its own ruling.
- **Test pitfalls:**
  - A warm stack reloads classes, but running production jobs keep their old code, so changes to production items (the poller and `IncidentManager` included) are proven through the production only on a fresh stack.
  - A persistent object a test still holds shows the values it was opened with, so wait helpers reopen the row on each poll (`Case.WaitRow`).
  - Watch tests need demo mode and the grant. A test that reruns the Roles step must restore the service role, as `Test.Install.Registry` does.
  - `Test.Watch.Poller`'s untagged failures now make `instance` incidents; `Case`'s cleanup removes them.
  - The lane-a shard (57 classes) runs locally as `ci/iris.sh shard lane-a --part 1/2` and `--part 2/2`, each alone in its call with nothing chained after it (about 377 s and 295 s fresh); use `--part k/3` if a part passes 480 s. The CI groups are unchanged.
