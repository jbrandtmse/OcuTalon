# Epic 5 Context: OcuTalon watches a production and explains what broke

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

A user asks OcuTalon in plain words to watch, or stop watching, an Interoperability production. New failures are picked up within seconds. A same-cause burst becomes a single incident under the settle rule. The Diagnosis agent then explains it: a plain-English cause, the element at fault and a proposed fix, with the evidence behind Show details. The incident moves through a fixed state table. Asked "is everything fine?", OcuTalon answers only from check results that code computes, so it never gives a false all-clear. This is the "what broke" half of the demo path (Break the feed, then one notice in about 35 s), and Epic 7's approve-and-fix builds on it.

## Stories

- Story 5.1: Ask OcuTalon to watch a production, and to stop
- Story 5.2: New failures are picked up within seconds
- Story 5.3: Same-cause failures become one incident by the settle rule
- Story 5.4: The diagnosis explains the cause from the failed messages
- Story 5.5: An incident moves through its states and closes
- Story 5.6: The production watch runs on every heartbeat
- Story 5.7: Asked whether everything is fine, OcuTalon never gives a false all-clear
- Story 5.8: Each noticed incident says what broke, with its evidence behind Show details

## Requirements & Constraints

- **Watching:**
  - A production is matched by display name across namespaces whose data database the service user may read.
  - For an unknown name, nothing is created; OcuTalon lists the productions it can see and asks which one was meant.
  - On the online demo, only Orders can be watched.
  - Stop removes only that session's watch. The watch appears in the background-check list.
- **Pickup:** within 15 s (typically under 3 s), with no wait for the heartbeat, no change to the watched production and no reliance on its alerts. No failure is ever batched twice or skipped, including across a restart.
- **Settle rule:** the notice step starts after 10 s with no same-cause failure, or 30 s after the first failure, whichever comes first. Both values are settings. A burst of 50 gives one incident with a notice count of 50. Later same-cause failures update only the running count: no second incident, no second notice.
- **Scope:** a failure tagged with a session's trace reference belongs to that session; an untagged one is `instance`. Local watchers of one production share an instance incident per cause, and each gets its own notification. A copy that a fix resent counts against the fix, never against a failure group.
- **Visibility:** until its notice, an incident is hidden from the snapshot, the guide and Break the feed, and no count is published.
- **Diagnosis:** gives a cause category, the element at fault, evidence references, a fix kind with parameters, the cause and fix as plain sentences, the item noun (singular and plural), and reasons with a confidence from 0 to 1. A typical diagnosis takes one model request. An invalid reply falls back: the failures stay grouped by the fixed rules, with no cause, no fix and a fallback flag.
- **Lifecycle:**
  - States: open (with the variants fallback, no fix, rejected and expired), awaiting approval, fixing, resolved and closed. Any other move is refused.
  - Dismiss is accepted only from a recipient session, on an open or resolved incident.
  - Quiet close after 15 min: resolved incidents always; open incidents only with demo mode off. Awaiting-approval and fixing incidents never close on their own.
  - After a close, a same-cause failure opens a new incident.
  - Incidents closed more than the retention period ago (90 days by default) are purged.
- **Heartbeat:** each due check runs once per tick, even after several missed runs. Every run records passed, failed (with the finding) or not checked (with the reason), plus the time and a trace target. A reader error or a timeout counts as not checked.
- **All-clear:** comes only from code. The guard strips reserved sentences and the banned phrases ("all good", "everything's fine", "everything is fine", "no issues", "no problems", "nothing to worry about") from model text. A failing check is named first.
- **Security:**
  - Start watch, stop watch and dismiss are safe but not read-only. They run in a user's turn without approval and are denied in an untrusted or tainted turn. Listing productions and `check_status` are read-only.
  - An injected "stop watching" stops nothing.
  - Diagnosis runs with provenance `untrusted`.
  - Credential-like setting values never leave the reader. A setting is credential-like when its name contains, case-insensitively, any of: credential, password, token, key, secret, passphrase, passwd, auth, bearer or cookie.
  - Database row ids never reach the model.
- **Timing:** the notice arrives within 60 s in 19 of 20 runs, with diagnosis within 20 s. This is measured in the rehearsal and never asserted in CI.

## Technical Decisions

- **Ownership (Lane A):**
  - Packages: `OcuTalon.Watch` (`FailurePoller`, `IncidentManager`, `Ops` = `WatchOps`, `Reader`, `EvidencePack`, `ErrorText`, `ItemNoun`, `Notice`), `OcuTalon.Checks` (`Process`, `Render`, `ReplyGuard`) and `OcuTalon.Tools`.
  - Tables: `BackgroundCheck`, `WatchMark`, `Incident` and `FailureGroup`.
  - Single event publishers: `IncidentManager` for `incident` and `watch.progress`, `Checks` for `check`.
  - Keys go in `Msg.Catalog.Watch`.
  - Edit only Lane A's region of the production XData. Never edit Lane B files (`Core`, `Data.Session`, `Data.Ownership`, `Live`, `Msg`, `Web`, `Schedule`); ask for properties instead.
- **Commands:** state-changing tools submit `OcuTalon.Msg.Command` verbs through `Core.Commands.Submit`, with origin `tool` and an `IdempotencyKey` made of the turn's `ItemId` plus the call's position. They return the owner's synchronous `CommandResult` and never write domain tables. Tests use a `CommandsIn` test double.
- **Reader:**
  - Only `Watch.Reader` switches namespace, in one `New $NAMESPACE` method, gated by `$SYSTEM.Security.CheckUserPermission`.
  - It reads only a namespace's own production: the running one, else the last active one (`Ens.Director.GetActiveProductionName()`), never other `Ens.Config.Production` rows.
- **What counts as a failure:**
  - a header with `Status` 8, whatever `IsError` says;
  - an event-log row of `Type` 2 or 6 that has no `SessionId`.

  The error sentence comes out of the "Terminating BP" wrapper, after redaction, through one helper, `Watch.ErrorText` (`Text`, plus `Summary` of at most 80 characters). The poller, the evidence pack and the notices all use it.
- **FailurePoller:**
  - An `Ens.InboundAdapter` with `CallInterval` 3 s.
  - It alone writes `WatchMark` (`MarkAt` and `Seen`, with a 2 s overlap), starting no earlier than the earliest watch's `CreatedAt`.
  - Each poll sends one `FailureBatch` per production and scope (at most 500), each in its own trace session, then saves the mark. Delivery is at least once, and `IncidentManager` drops repeats by `h<HeaderId>` or `l<LogId>`.
- **IncidentManager:**
  - The only writer of `Incident` and `FailureGroup`.
  - Groups by production, scope, item and error pattern (digits masked), keeping the newest 1000 keys in `FailureGroup.Seen`.
  - An incident gets its `Ref` at the first failure.
  - One instance per new group waits on settle, re-reading the row on every wake (`watch.settleQuietSeconds` and `watch.settleMaxSeconds` through `Data.Setting`), and emits `watch.progress` with `noticed`, `settling` and `diagnosing`.
  - `Count` and `NoticeCount` are stored separately.
  - Other parts reach it only through `IncidentCommand` (`dismiss`, `closeForReplay`, `closeQuiet`, each synchronous), `ApprovalOutcome` or `FixResult`.
- **Diagnosis:**
  - Runs in the incident's own trace session: clear `%SessionId`, keep `SuperSession`.
  - One `diagnose` request goes through `Decide`, with `ItemId` set to the incident `Ref` and `EvidencePack.Build(source)` (live reader or recorded snapshot) as input.
  - The reply class is `Watch.Msg.DiagnosisPayload`.
  - The read-only `OcuTalon.Tools.Watch` tools take no arguments and read only the incident in context. Event-log rows are referred to by a pack-local `logRef`.
  - `IncidentManager` consumes the result itself, never through `OutcomeRouter` (usable is `act`, fallback is `tellnow`), and stores it on the incident row.
- **Notices:**
  - `Watch.Notice` builds keys and slots only: one kind-`incident` `Notification` per `Session.Recipients(ownerRef, incidentRef)`.
  - Slots: UTC ISO times, integer counts, `itemNoun: {"one","other"}`, and model text as plain sentences without times. Only the `*Out` operations render.
  - Epic 5 stores a usable data-format diagnosis and leaves the incident unnoticed: Story 7.2 sends its with-fix notice.
  - `Live.Payload.Incident.FromRow` uses object access only, never SQL (`/state` has no SQL grant), and reads requests through `Incident.RequestRefs`.
  - Payloads are the entity's full view, keyed by `Ref` and published after commit.
- **Transitions:** one table, unit-tested row by row, covering the overlap rows (one fix at a time per incident) and every refused move. A cancelled request changes nothing. Story 5.5 creates `Fix.Msg.Execute` and `FixResult`; Epic 7 handles them.
- **Checks:**
  - A `Tick` (from `HeartbeatIn`, or sent directly in tests) runs the due `BackgroundCheck` rows. A watch checks the running state, new errors, the open incident and the latest run time.
  - `Checks` publishes `check` on change and on watch start or stop.
  - It sends `closeQuiet` once a failure is more than 15 min old, and sends no finding Items yet.
- **All-clear:**
  - `Checks.Render(results, *rows)` returns a key plus rows `{result, entry, finding, checkedAt}`.
  - `check_status` is `TrustedOutput` and fills `HostData.checks`.
  - `ReplyGuard` extends `Bridge.Ext.ReplyFilter`, replacing Epic 0's stub, and runs exactly once before anything leaves `Decide`.
- **Conventions:**
  - Tools declare `CLASSIFICATION`, `READONLY`, `TRUSTEDOUTPUT`, `STEPLABEL` and `RESOURCES` class parameters (optionally `<NAME>`-suffixed). The watch tools are trusted output.
  - Results return dynamic objects through `Tools.Result`.
  - Refs come from `Bridge.Ids.NewRef()`. Times are UTC, rendered only through `Data.Time`.
  - Tests live in `OcuTalon.Test.<Area>`, with recorded snapshots and the mock scenarios in `ci/mock/scenarios/A/`.

## UX & Interaction Patterns

- Plain English: no class names, error codes or stack traces outside Show details, and quoted values in single quotes. Use the catalog's exact texts (watch confirmation, unknown production, Orders-only on the demo, check sentences, no-fix and fallback notices).
- No counts before the notice: Break the feed's progress lines come from `watch.progress`.
- A check row shows the name, the schedule ("Live, plus a check every minute"), the last run, the result and a trace link to the latest run. Rows under a "fine?" reply are code-computed: Passed, Failed or Not checked.
- Show details shows the cause category, the element at fault, a sample failed message with its error, the failures per item with first and last times, and the trace targets `diagnosis`, `sample` and `firstFailure`.

## Cross-Story Dependencies

- **Story order:** Story 5.8 (split from 5.4) runs after 5.4 and before 5.5. It received 5.3's "one notice per watcher". The with-fix notice, its demo slots and the request `Result` counts moved on to Stories 7.2 and 7.4.
- **Upstream:**
  - Epic 0: the Orders production and its tagged failure fixtures; `Commands.Submit`, `IncidentCommand`, `Live.Payload.Incident`, the `Catalog.Watch` keys and the pinned `Checks.Render` signature.
  - Epic 1: `Decide`, the `DiagnosisAgent` runner and the fallback.
  - Epic 3: the gate's classifications and resources, and `ApprovalOutcome`.
  - Epic 2: `Session.Recipients`, the ownership API's notice filter and `Conversation` calling `Render`. The page's check row still needs the whatFailed slot and `Check.FromRow`.
- **Downstream:**
  - Epic 7: dry run, `Raise`, with-fix notice, the `Execute`/`FixResult` handlers, and `Fix.Run.Sweep` through `Checks`.
  - Epic 6: incident cards and Show details.
  - Epic 8: the heartbeat task and check rows.
  - Epic 4: Break the feed reads `NoticedAt` and sends `closeForReplay`.
  - Epic 30: the purge task (until then, tests call `Purge(daysToKeep)` directly) and the stopped-production and disabled-item findings.
  - Epic 9: at least 80% of causes right on the evaluation set.
