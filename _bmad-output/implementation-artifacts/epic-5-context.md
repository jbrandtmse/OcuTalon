# Epic 5 Context: OcuTalon watches a production and explains what broke

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Epic 5 (Lane A) builds OcuTalon's IRIS watch, the middle of the two-minute demo between "watch the Orders production" and "approve the fix". A user asks in plain words to watch a production, or to stop. New failures are picked up within seconds without waiting for the heartbeat, and same-cause failures become one incident by the settle rule. The Diagnosis agent explains the incident from the failed messages: a plain-English cause, the element at fault and a proposed fix, with the evidence behind Show details. Each incident then moves through a fixed state table and closes. The heartbeat runs every watch's check, and asked whether everything is fine, OcuTalon answers from code-computed check results, so it never gives a false all-clear. The dry run and the approval request (Epic 7) and the incident cards (Epic 6) build on this epic.

## Stories

- Story 5.1: Ask OcuTalon to watch a production, and to stop
- Story 5.2: New failures are picked up within seconds
- Story 5.3: Same-cause failures become one incident by the settle rule
- Story 5.4: The diagnosis explains the cause from the failed messages
- Story 5.5: An incident moves through its states and closes
- Story 5.6: The production watch runs on every heartbeat
- Story 5.7: Asked whether everything is fine, OcuTalon never gives a false all-clear

## Requirements & Constraints

- **Watching:** a plain-words request creates a production watch with no configuration, and the chat confirms what will be watched. Names match by display name in any namespace whose data database the service user may read. For an unknown name, OcuTalon creates no watch, lists the productions it can see and asks which one was meant. On the online demo only Orders can be watched. "Stop watching" removes that session's watch and nothing else. The watch shows in the page's background-check list.
- **Reacting:** new failures are picked up within 15 s (typically under 3 s). This works on any production without changing it or relying on its alerts. No failure is batched twice or skipped, including across restarts. OcuTalon reports only something new and never repeats an incident.
- **Settle rule:** the notice step starts after 10 s with no new same-cause failure, or 30 s after the first failure, whichever comes first (both values come from settings). A burst of 50 gives one incident with a notice count of 50. Later same-cause failures update the count and never cause a second incident or notice.
- **Shared incidents:** a failure tagged with a session stays that session's. Untagged (`instance`) failures give one incident per cause, shared by every session watching that production, with one notice per watcher.
- **Diagnosis:** names a cause category and the element at fault (field, setting or endpoint), backed by evidence from the failed messages, their errors and the trace. A typical diagnosis takes one model request.
- **Notice variants:**
  - with a fix: a data-format cause; this epic sends the notice key, and Story 7.2 adds the dry run and the approval;
  - no fix: any other cause, `unknown` included, with no approval request;
  - fallback: grouped by fixed rules (production item plus error pattern), claims no cause and proposes no fix.
- **Time budget (NFR-7):** at most 60 s from Break the feed to the notice in 19 of 20 runs: pickup ≤15 s, settle ≤30 s, diagnosis ≤20 s, delivery ≤5 s, about 30–35 s typical. These times are measured in the clean-machine rehearsal and are never asserted in CI.
- **Closing:**
  - a resolved incident closes after 15 quiet minutes, on Dismiss, or for a replay;
  - an open incident (fallback, no fix, rejected or expired) closes on Dismiss, and after 15 quiet minutes only with demo mode off;
  - an incident awaiting approval or fixing never closes on its own;
  - a same-cause failure after closing opens a new incident.
- **No false all-clear:** code alone decides whether an all-clear may be given. The model can't add one, and every all-clear in the text comes from that computation. Step 1 tests: with Orders failing, "is everything OK?" gets no all-clear, and that still holds when a mock model claims everything is fine.
- **Retention:** incidents closed longer ago than `daysToKeep` (default 90) are deleted with their failure groups; younger ones stay.
- **Plain English:** class names, error codes and production class paths appear only behind Show details.

## Technical Decisions

- **Ownership (Lane A):**
  - production items `FailurePoller`, `IncidentManager` and `WatchOps` (`OcuTalon.Watch.FailurePoller`, `.IncidentManager`, `.Ops`) and `Checks` (`OcuTalon.Checks.Process`);
  - tables `BackgroundCheck`, `WatchMark`, `Incident` and `FailureGroup`;
  - the `incident`, `watch.progress` and `check` events: `IncidentManager` alone writes incidents and failure groups and publishes `incident` and `watch.progress`, and `Checks` alone publishes `check`;
  - catalog keys in `OcuTalon.Msg.Catalog.Watch`, mock scenarios only under `ci/mock/scenarios/A/`, and edits only in Lane A's region of the production class.

  Lane B owns `Session`, `Ownership`, `Live`, `Msg`, `Core` and `Schedule` (`HeartbeatIn`). Ask Lane B for any property you need on its classes.
- **Commands (AD-1):**
  - the watch and dismiss tools submit `OcuTalon.Msg.Command` verbs through `OcuTalon.Core.Commands.Submit`, which forces origin `tool` inside a bridge context;
  - each command carries an `IdempotencyKey`: the turn's `ItemId` plus the call's position in the turn;
  - each tool returns the owner's synchronous `CommandResult`;
  - tools never write domain tables, and their tests run against a `CommandsIn` test double.
- **Tool classes:**
  - each tool declares `CLASSIFICATION<NAME>`, `READONLY<NAME>`, `TRUSTEDOUTPUT<NAME>`, `STEPLABEL<NAME>` and `RESOURCES<NAME>` as class parameters;
  - start watch, stop watch and dismiss are safe but not read-only; listing productions and `check_status` are read-only, and `check_status` is also `TrustedOutput`;
  - Diagnosis's toolset `OcuTalon.Tools.Watch` is read-only, and its output (message bodies, event-log text) is never trusted;
  - results go through `OcuTalon.Tools.Result` as dynamic objects or text, never as pre-encoded JSON;
  - tools run inside AI Hub callbacks, so they make no `%AI` native calls and run no Python.
- **Reading IRIS (AD-3):** only `OcuTalon.Watch.Reader` switches namespace, in one `New $NAMESPACE` method. It skips namespaces whose data database the service user can't read (`$SYSTEM.Security.CheckUserPermission`). On build 154, a failed Orders message is recognized by its header `Status` 8 plus its event-log row, because an asynchronous send leaves `IsError` 0. Its failure sentence is parsed out of the "Terminating BP" wrapper.
- **Scope:** a failure belongs to the session whose `TraceRef` equals the message's `SuperSession`, and otherwise to `instance`. A failed copy that a fix registered is attributed to that fix, never to a failure group. `OcuTalon.Data.Session.Recipients(ownerRef, incidentRef)` resolves which sessions receive an incident.
- **Incident lifecycle (AD-15):**
  - the incident gets its `Ref` at its first failure;
  - before the notice, only `watch.progress` events go out (`noticed`, `settling`, `diagnosing`), keyed by that `Ref` and with no counts;
  - one `IncidentManager` instance per new group waits on the settle rule and re-reads the group row on each wake;
  - `NoticedAt` is set only at the notice, and the ownership API hides the incident until then;
  - `Count` and `NoticeCount` are stored separately.

  Everyone else talks to `IncidentManager` through `IncidentCommand` (`dismiss`, `closeForReplay`, `closeQuiet`, answered synchronously; a dismiss only from a recipient session), `ApprovalOutcome` and `FixResult`. One transition table applies (states in `OcuTalon.Msg.Enum`; the open variant is stored beside the state). Its unit test covers every row, the overlap rows and every refused move. Story 5.5 creates the messages `OcuTalon.Fix.Msg.Execute` and `.FixResult`.
- **Diagnosis pipeline (AD-6/7/8/30):**
  - the diagnosis runs in its own trace session, clearing `%SessionId` and keeping the `SuperSession`;
  - `OcuTalon.Watch.EvidencePack.Build(source)` builds the pack from the live reader or from a recorded snapshot (`ocutalon.readerSnapshot/1` under `eval/`). Credential-type setting values are removed;
  - the pack goes as the rendered `Input` of a `diagnose` request through `Decide`, which answers with a `DecisionResponse`. A diagnosis never goes to `OutcomeRouter`;
  - the reply is validated against `OcuTalon.Watch.Msg.DiagnosisPayload` (cause category, element, evidence refs, fix kind and parameters, cause and fix sentences, `ItemNoun` with its one and other forms, reasons, confidence 0–1). A reply that fails validation is `invalid`;
  - only the bridge classifies fallbacks;
  - when no usable diagnosis gives a noun, code takes it from the fixed map `OcuTalon.Watch.ItemNoun` (the Orders class gives "order"/"orders", anything else "message"/"messages");
  - a fallback group's error summary is the error's first sentence, at most 80 characters, passed through `OcuTalon.Bridge.Redact`.
- **Notices (AD-32):**
  - one `OcuTalon.Msg.Notification` of kind `incident` per recipient session, with a catalog key and `Slots`;
  - slots carry counts as integers, times as UTC ISO 8601, `itemNoun: {"one","other"}`, and model sentences without times;
  - producers never render text. Render tests go through `OcuTalon.Msg.Catalog.Render`;
  - the README link in server text is `https://github.com/jbrandtmse/OcuTalon#readme`.
- **Live payload (AD-12):** each `incident` event carries the full current view in `OcuTalon.Live.Payload.Incident`, never a delta. That includes `CauseCategory`, `Element`, `Evidence`, `Groups`, `Requests` (each with `Ref`, `State` and `Result`) and `TraceTargets` (`diagnosis`, `sample`, `firstFailure`, as `TraceHeaderId` plus `TraceNamespace`). Events are published through `OcuTalon.Live.Publish` after commit, never inside an open transaction.
- **Checks (AD-18/28):**
  - a `Tick` runs each due `BackgroundCheck` once, even after several missed runs;
  - each run records its last run, a result (`passed`, `failed` with the finding, or `not_checked` with the reason), the time and its trace header id. A reader error gives `not_checked`;
  - a `check` event also goes out when a watch starts or stops;
  - `Checks` sends `closeQuiet` for incidents whose last failure is more than 15 minutes old;
  - this epic turns no finding into an Item (that moved to Story 30.4).
- **All-clear (AD-28/31):**
  - `OcuTalon.Checks.Render(results, *rows)` returns the catalog key and code-computed rows `{result, entry, finding, checkedAt}`;
  - `check_status` puts the results in `HostData.checks`, and `Conversation` (Lane B) passes them to `Render` without reading them;
  - `OcuTalon.Checks.ReplyGuard` extends `OcuTalon.Bridge.Ext.ReplyFilter` and replaces Epic 0's pass-through stub. It runs exactly once, before `Decide` records anything, removes the reserved sentences and the banned phrases, and keeps the rest of the text.
- **Conventions:**
  - times are stored as UTC and rendered only through `OcuTalon.Data.Time`;
  - the Watch area's `Purge(daysToKeep)` declaration is called directly in tests until Story 30.2's task exists.

## UX & Interaction Patterns

- **Exact texts:**
  - watch confirmation: "I'll watch the Orders production and stay quiet unless something needs you.";
  - unknown production: "I can't find a production called '{name}'. I can see: {list}. Which one did you mean?";
  - another production on the online demo: "On the online demo I can only watch the Orders production. Install OcuTalon to watch your own productions: {README link}".
- **Background-check row:** name ("Orders production"), schedule ("Live, plus a check every minute"), last run, result and a trace link to the latest run.
- **Before the notice:** there is no incident card. Only Break the feed's progress lines show, driven by `watch.progress` `noticed`, `settling` and `diagnosing` (the page shows "OcuTalon noticed failures in the Orders production", "Waiting for the failures to settle", "Working out the cause from the failed messages"), with no counts.
- **Notices:** numbers first, then the cause, then the choice. The no-fix and fallback texts are fixed in the catalog and end with "Nothing was changed." The fallback "Failures:" lines give the item name, the count, the error summary in single quotes and the first time.
- **Show details** needs the cause category and element, a sample failed message with its error, failures per item with first and last times, and trace links to the sample and the first failure. The incident's trace link opens the diagnosis session.
- **Reserved sentences:** "Everything I checked passed." appears only when every check passed. Otherwise the failing entry comes first ("Not everything: {what failed, with its time}."), then "Everything else I checked passed." only if other checks passed. With nothing watched, the answer is "I'm not watching any productions yet, so I can't say. Ask me to watch one." The guard always removes the banned phrases: "all good", "everything's fine", "everything is fine", "no issues", "no problems", "nothing to worry about".

## Cross-Story Dependencies

- **Within the epic:**
  - 5.1's watches (`BackgroundCheck` rows) feed 5.2's poller and 5.6's checks;
  - 5.2's batches feed 5.3's grouping, and 5.4 diagnoses at the end of the settle rule;
  - 5.5's transition table governs every state change in 5.3, 5.4 and 5.6;
  - 5.6's check results feed 5.7's `check_status` and `Render`.
- **Merged and available:**
  - Epic 0: contracts, `Commands.Submit`, the catalog renderer, the Orders production in OCUORDERS and the recorded snapshot;
  - Epic 1: `Decide`, the `DiagnosisAgent` runner, and the fixture `OcuTalon.Tools.Watch` that Story 5.4 replaces;
  - Epic 2: `Session.Recipients`, the ownership API's `NoticedAt` filter, `Live.Publish`, `BridgeSink`, and `Conversation` calling `Render`;
  - Epic 3: the gate's classification, the Approval API and `ApprovalOutcome`.
- **Not yet merged, so tests use fixtures or direct calls:**
  - Break the feed (Epic 4): fixtures put failing Orders messages tagged with a test session's `TraceRef`;
  - `HeartbeatIn` (Epic 8): tests send `Tick` directly;
  - the incident cards (Epic 6);
  - Epic 7: the dry run, approval, `FixExecutor`, later requests and `Fix.Run.Sweep`;
  - Epic 30: the purge task (30.2) and the stopped-production and disabled-item findings (30.4);
  - Epic 9: evaluation runs drive `IncidentManager` and `EvidencePack` with owner `eval`, sending to `EvalSink`;
  - Epic 11: the end-to-end path.
- **Tooling:** Story 5.1 also fixes `ci/warm.sh` so that it prints `READY` only after the warm stack's `RESULT OK`. Until then, don't treat a warm stack's `READY` as proof that it compiled.
