# Epic 5 Context: OcuTalon watches a production and explains what broke

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

A user asks OcuTalon in plain words to watch, or stop watching, an Interoperability production. New failures are picked up within seconds, without waiting for the heartbeat, and a same-cause burst becomes one incident under the settle rule. The Diagnosis agent then explains it: a plain-English cause, the element at fault and a proposed fix, with the evidence behind Show details. The incident moves through a fixed state table and can be dismissed from the chat. The heartbeat checks every watched production each minute. Asked "is everything fine?", OcuTalon answers only from check results that code computes, so it never gives a false all-clear. This epic is the "what broke" half of the demo path (Break the feed, then one notice in about 35 s). Epic 7's approve-and-fix completes the path.

## Stories

- Story 5.1: Ask OcuTalon to watch a production, and to stop
- Story 5.2: New failures are picked up within seconds
- Story 5.3: Same-cause failures become one incident by the settle rule
- Story 5.4: The diagnosis explains the cause from the failed messages
- Story 5.5: An incident moves through its states and closes
- Story 5.6: The production watch runs on every heartbeat
- Story 5.7: Asked whether everything is fine, OcuTalon never gives a false all-clear
- Story 5.8: Each noticed incident says what broke, with its evidence behind Show details
- Story 5.9: Ask OcuTalon in the chat to dismiss an incident

## Requirements & Constraints

- **Watching:**
  - A production is matched by display name across the namespaces whose data database the service user may read.
  - For an unknown name, nothing is created; OcuTalon lists the productions it can see and asks which one was meant.
  - On the online demo, only Orders can be watched.
  - Stop removes only that session's watch. The watch appears in the background-check list.
- **Pickup:** within 15 s (typically under 3 s), with no change to the watched production and no reliance on its alerts. No failure is batched twice or skipped, across a restart too.
- **Settle rule:** the notice step starts after 10 s with no same-cause failure, or 30 s after the first failure, whichever comes first. Both values are settings. A burst of 50 gives one incident with a notice count of 50. Later same-cause failures update only the running count, never giving a second incident or notice.
- **Scope:** a failure tagged with a session's trace reference belongs to that session; an untagged one is `instance`. Local watchers share one `instance` incident per cause, and each watcher gets its own notification. A resent copy counts against its fix, never against a failure group.
- **Visibility:** until its notice, an incident is hidden from the snapshot, the guide and Break the feed, and no count is published.
- **Diagnosis:**
  - It gives:
    - the cause category and the element at fault;
    - evidence references;
    - a fix kind with its parameters;
    - the cause and fix summary as plain sentences;
    - the item noun, singular and plural;
    - reasons, with a confidence from 0 to 1.
  - An invalid reply falls back: the failures stay grouped by the fixed rules, with no cause, no fix and a fallback flag.
- **Lifecycle:**
  - States: `open` (variants `fallback`, `no_fix`, `rejected`, `expired`), `awaiting_approval`, `fixing`, `resolved` and `closed`. Every other move is refused.
  - Dismiss is accepted only from a recipient session, on an open or resolved incident.
  - Quiet close after 15 min: resolved incidents always; open ones only with demo mode off. Awaiting-approval and fixing incidents never close this way.
  - After a close, a same-cause failure opens a new incident.
  - Incidents closed longer ago than `daysToKeep` (90 by default) are purged.
- **Chat dismiss:** UJ-1's rejected path tells the user to dismiss the incident in the chat. The tool may pick only among the session's own open or resolved incidents.
- **Heartbeat:**
  - Each due check runs once per tick, even after missed runs.
  - Each run records the result (`passed`, `failed` with the finding, or `not_checked` with the reason), the time and the latest run's trace header id. A reader error or timeout counts as `not_checked`.
  - No finding Items are sent yet (they come in Story 30.4).
- **All-clear:**
  - It comes only from code.
  - Model text loses the reserved sentences and the banned phrases ("all good", "everything's fine", "everything is fine", "no issues", "no problems", "nothing to worry about").
  - A failing or unchecked check is named first.
  - With nothing watched, OcuTalon says it can't tell yet.
- **Security:**
  - Start watch, stop watch and dismiss are safe but not read-only. They run in a user's turn without approval and are denied in an untrusted or tainted turn. `list_productions` and `check_status` are read-only.
  - An injected "stop watching" stops nothing.
  - Diagnosis runs with provenance `untrusted`.
  - Credential-like setting values never leave the reader. A setting is credential-like when its name contains, case-insensitively, any of: credential, password, token, key, secret, passphrase, passwd, auth, bearer or cookie.
  - Database row ids never reach the model.
- **Timing:** the notice arrives within 60 s in 19 of 20 runs, with the diagnosis within 20 s. These times are measured in the rehearsal and never asserted in CI.

## Technical Decisions

- **Ownership (Lane A):**
  - Packages: `OcuTalon.Watch` (`FailurePoller`, `IncidentManager`, `Ops` = `WatchOps`, `Reader`, `EvidencePack`, `ErrorText`, `ItemNoun`, `Notice`), `OcuTalon.Checks` (`Process`, `Render`, `ReplyGuard`), `OcuTalon.Tools` and `OcuTalon.Fix.Msg`.
  - Tables: `BackgroundCheck`, `WatchMark`, `Incident` and `FailureGroup`.
  - Single publishers: `IncidentManager` for `incident` and `watch.progress`, and `Checks` for `check`.
  - Catalog keys go in `Msg.Catalog.Watch`. Mock scenarios are files under `ci/mock/scenarios/A/` only.
  - Edit only Lane A's region of the production XData. Never edit Lane B files (`Core`, `Data.Session`, `Data.Ownership`, `Live`, `Msg`, `Web`, `Schedule`); ask for properties instead.
- **Messages, not calls:** components reach each other only through messages addressed by item name. Tools and agents may use `Msg`, `Data`, `Watch.Reader` and `Commands.Submit`. `Checks` may call `Fix.Run.Sweep()`.
- **Tool commands:** a state-changing tool submits an `OcuTalon.Msg.Command` verb through `Core.Commands.Submit` and returns the owner's synchronous `CommandResult`. It never writes domain tables.
  - Origin is `tool`. The `IdempotencyKey` is the turn's `ItemId` plus the call's position in the turn.
  - Among the verbs `CommandsIn` accepts from origin `tool` are start watch, stop watch and a dismiss of one of the session's own incidents.
  - Tests use a `CommandsIn` test double in `OcuTalon.Test.Watch`.
- **Incident commands:** `IncidentManager` answers each `IncidentCommand` (`dismiss`, `closeForReplay`, `closeQuiet`) synchronously, checking in this order:
  1. any other verb is `unknown_command`;
  2. a missing incident is `not_found`, and so is a `dismiss` from a session outside `Session.Recipients`; a failed read of the recipients is `failed`, without `Data`;
  3. a `closeQuiet` whose `LastAt` is not more than `QUIETSECONDS` (900) old is `not_quiet`;
  4. a move the table refuses is `not_allowed`;
  5. an accepted move is `Ok` 1 with `Outcome` `closed`.

  Every answer that found the incident for its caller carries `Data` `{"state", "openVariant"}`, the state after the command. `Message` is developer text: each channel shows its own words to users (Stories 5.9 and 6.4). The row is the idempotency, so a repeated dismiss finds `closed` and answers `not_allowed`. `closeForReplay` and `closeQuiet` check no session.
- **Reader:** only `Watch.Reader` switches namespace, in one `New $NAMESPACE` method gated by `$SYSTEM.Security.CheckUserPermission`. It reads only a namespace's own production (the running one, else the last active one).
- **Failures:** a header in `Status` 8, whatever `IsError` says, or an event-log row of `Type` 2 or 6 with no `SessionId`. `Watch.ErrorText` (`Text`, and `Summary` of at most 80 characters) gives the redacted error sentence.
- **Pipeline (built):**
  - `FailurePoller` (`CallInterval` 3 s) alone writes `WatchMark`, and sends `FailureBatch`es that `IncidentManager` dedupes.
  - `IncidentManager` alone writes `Incident` and `FailureGroup`, and groups by production, scope, item and error pattern. It settles on `watch.settleQuietSeconds` and `watch.settleMaxSeconds`, and keeps `Count` apart from `NoticeCount`.
  - It diagnoses in the incident's own trace session through one `diagnose` request to `Decide` (`ItemId` = the incident `Ref`, reply class `Watch.Msg.DiagnosisPayload`), and consumes the result itself, never through `OutcomeRouter`.
  - `Watch.Notice` builds only keys and slots. A usable data-format diagnosis stays unnoticed until Story 7.2.
- **Transitions:**
  - One table, with a unit test for every row and every refused move.
  - In the overlap rows, a request counts as pending while it is `pending`, or `approved` while the incident is still `awaiting_approval`.
  - An `ApprovalOutcome` that its request's row doesn't show is refused.
  - A `FixResult`'s own request never counts as waiting. The earliest waiting request, in `RequestRefs` order, gets the next `Execute`.
  - A cancelled request changes nothing.
- **Checks:**
  - `Checks` (`OcuTalon.Checks.Process`) handles a `Tick` from `HeartbeatIn`, or one sent directly in tests, by running the due `BackgroundCheck` rows. A watch's check covers the running state, new errors, the open incident and the latest run time, all through `Watch.Reader`.
  - It publishes `check` (name, schedule, last run, result and trace target) when a row changes, and when `WatchOps` starts or stops a watch.
  - It sends `closeQuiet` for each unclosed incident whose last failure is more than 15 min old.
  - Payloads are the entity's full view keyed by `Ref`, published through `Live.Publish` after commit, with trace targets as `TraceHeaderId` plus `TraceNamespace`.
- **All-clear:**
  - `Checks.Render(results, *rows)`, Epic 0's pinned signature, returns a catalog key plus rows `{result, entry, finding, checkedAt}`.
  - `check_status` is `TrustedOutput` and fills `HostData.checks`. `Conversation` (Lane B) calls `Render` after the guard.
  - `ReplyGuard` extends `Bridge.Ext.ReplyFilter`, replacing Epic 0's stub, and runs exactly once before anything leaves `Decide`.
- **Conventions:**
  - Tools declare the class parameters `CLASSIFICATION`, `READONLY`, `TRUSTEDOUTPUT`, `STEPLABEL` and `RESOURCES`, optionally `<NAME>`-suffixed.
  - Tools return a dynamic object through `Tools.Result`. Tool names are constants in `OcuTalon.Tools.Names`.
  - An SQL reserved word keeps its name and gets an `SqlFieldName` (`Count` → `FailureCount`) or an `SqlTableName` (`Fix.Msg.Execute` → `FixExecute`).
  - Refs come from `Bridge.Ids.NewRef()`.
  - Times are UTC ISO 8601 to the second, rendered only through `Data.Time`.
  - Product settings are read through `Data.Setting.Get`.

## UX & Interaction Patterns

- Plain English: no class names, error codes or stack traces outside Show details. Quoted values use single quotes.
- Use the catalog's exact texts:
  - the watch confirmation, "I'll watch the Orders production and stay quiet unless something needs you.";
  - the unknown-production and Orders-only replies;
  - the check sentences;
  - the no-fix and fallback notices.
- A check row shows the name ("Orders production"), the schedule ("Live, plus a check every minute"), the last run, the result and a trace link to the latest run. Under a "fine?" reply, rows are code-computed: Passed, Failed or Not checked.
- No counts appear before the notice. Break the feed's progress lines come from `watch.progress`.
- Show details holds the cause category, the element at fault, a sample failed message with its error, the failures per item, and the trace targets `diagnosis`, `sample` and `firstFailure`.

## Cross-Story Dependencies

- **Run order:** 5.1, 5.2, 5.3, 5.4, 5.8, 5.5, 5.9, 5.6, 5.7.
  - Story 5.8 was split from 5.4, and Story 5.9 from 5.5.
  - 5.9 builds on 5.5's `dismiss` command and its result codes.
  - The with-fix notice and the request `Result` counts moved to Stories 7.2 and 7.4.
- **Upstream:**
  - Epic 0: the Orders production and its tagged failure fixtures, `Commands.Submit`, `IncidentCommand`, the `Catalog.Watch` keys and the pinned `Checks.Render`.
  - Epic 1: `Decide`, the agent runners and the fallback.
  - Epic 3: the gate's classifications and `ApprovalOutcome`.
  - Epic 2: `Session.Recipients`, the ownership notice filter, and `Conversation` calling `Render`.
  - Lane B's `HeartbeatIn` sends the `Tick`.
  - The page's check row still needs a whatFailed slot (DW-90) and `Live.Payload.Check.FromRow`, which replaces the web layer's copy (DW-66).
- **Downstream:**
  - Epic 7: the dry run, `Raise`, the with-fix notice, the `Execute`/`FixResult` handlers, and `Fix.Run.Sweep` called on each `Tick`.
  - Epic 6: incident cards, Show details and the card's Dismiss (6.4), which shares the incident-command results.
  - Epic 8: the heartbeat task and the page's check rows.
  - Epic 4: Break the feed reads `NoticedAt` and sends `closeForReplay`.
  - Epic 30: the purge task (until then, tests call `Purge(daysToKeep)` directly), and the stopped-production and disabled-item findings.
  - Epic 9: at least 80% of causes right on the evaluation set.
