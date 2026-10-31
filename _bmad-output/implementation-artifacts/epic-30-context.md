# Epic 30 Context: Lane A post-demo hardening

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Epic 30 finishes the Lane A parts of the demo-path stories that the owner moved past the demo path. Each part must land before 1.0.0:

- Long conversations are compacted before their requests near the size limit.
- Old messages and records are purged every day by the standard purge tasks.
- An approved risky tool call runs exactly once, from its stored row, with no model.
- A stopped production or a disabled item reaches the user once.
- A resend that is mixed, still running, stopped partway or unable to start says exactly how far it got, and never claims a change that did not happen.

Each part closes a gap that the demo path left open and that the ledger tracks. Stories 30.2 and 30.3 are done. 30.4 and 30.5 come next, then 30.1, which waits on Epic 9.

## Stories

- Story 30.1: Long conversations are compacted under the limit
- Story 30.2: Old messages and records are purged on schedule (done)
- Story 30.3: An approved tool call runs exactly once, with no model (done)
- Story 30.4: A stopped production or a disabled item is reported once
- Story 30.5: Mixed and unfinished resends say how far they got

## Requirements & Constraints

- **Request size.** No model request may go over 100,000 input tokens, and a mock conversation long enough to compact must show a largest request under that. The loop bound only holds once every turn flagged above 40,000 tokens is actually compacted: 40,000 + 3 × 10,000 of tool results + 3 × 8,000 of output = 94,000 tokens at Chat's 4 iterations.
- **Retention (built).**
  - `HeartbeatIn` and `Checks` messages are kept 7 days, all other Interoperability data 90.
  - Decisions, usage and closed incidents (with their groups and FixRuns) are kept 90 days. An AI session goes a day after no conversation link names it.
  - The audit log is never touched.
  - History reads OcuTalon's and the bridge's tables, never messages.
- **Approval before risk (built).** An approved call runs exactly once, calls no model, and reports only through the row and `approval.result` (`{"ref"}`), never the tool's result text.
- **Audit.** Every approval and action entry carries the time, the IRIS user and the session, and is written only through `Bridge.Audit`. Tests read entries back by polling with a timeout (`Test.Bridge.AuditLog.Wait`), because IRIS writes some rows late.
- **Only new findings.**
  - The same finding is never sent twice. Two Ticks after a test production stops give exactly one finding Item.
  - What counts as "new" lives in rows, never in memory (AD-5).
- **Honest results.**
  - Each fix run gets exactly one final `FixResult`.
  - Nothing is resent behind the user's back, and a copy that fails again is never retried without a new approval.
  - A result's text never claims a change that did not happen. "Had changed since the dry run" is only for a target that really changed.
- **Stored data.** Persistent and message classes are append-only (AD-5), with a committed `Storage` block, and the CI storage diff runs against the last tag. Any new column needs its own veto window.
- **Public text.** New public wording (a reason sentence, a key, a text) is a veto-window item. Text reaches users only as catalog keys and slots, rendered by the `*Out` operations through `Msg.Catalog.Render`.

## Technical Decisions

**30.1 Compaction (AD-20, AD-6, AD-8).**

What exists:

- `Bridge.Process.Decide` estimates the first request: `RequestSize.AgentChars` and `HistoryChars`, plus the input, at `StepBuffer.CHARSPERTOKEN` characters per token.
- On a turn's clone, Decide sets `Request.Compact` to 1 above `COMPACTTOKENS` (40,000), and takes the fallback `too_large` above `RequestTokenLimit` (at most 100,000).
- The runner ignores the flag today. `Adapter.Agent.Answer` sends kind `tool` to `Bridge.Replay.Run`. A linked turn goes through `AnswerLinked`, in this order:
  1. the link lock;
  2. `OpenSession` or `NewSession`;
  3. `Converse` (`Chat`);
  4. `SaveLinked`: `%Save`, then `ConversationLink.Point`.
- `Bridge.Compaction` holds `PREFIX` (`OCUTALON-COMPACTION-V1`) and `Prompt()`. Mock scenarios `summary.json` and `summary-off-schema.json` exist under `ci/mock/scenarios/A/`.
- Code-rule pins: only `AgentRunner` and `Adapter.Agent` may chat or make sessions (`CHATTERS`, `SESSIONMAKERS`), and `LINKNAMERS` lists who may name the link. A compaction class outside the adapter must be added to them on purpose.
- `Bridge.Purge` (30.2) deletes the session a fork or a rotation leaves behind a day later, so 30.1 adds no cleanup. It relies on only the runner saving AI sessions in OCUTALON and pointing the link right after the save, so keep that true for the fork.

What to build:

- **Where it runs.** The runner compacts in its own job, outside every callback, before `Chat`. No callback may call AI Hub's native library (S4 deadlock).
- **The call.** `ForkAndSummarize(summarizerProvider, "", k, prompt, 0)`, where `k` keeps the last user turn whole and comes from `GetContext()`. With no older history there is no compaction. `Summarize` in place is never used.
- **The switch.** Move the link to the fork only after the check passes: the first non-system message is a user message, and every tool result follows its tool call. Then `%Save` the fork.
- **The fallback.** An exception (it arrives as `<%AICore>InternalError`) or a failed check gives a fresh AI session, seeded with a code-written summary of the stored user and assistant texts. It is never the turn's `FallbackReason`.
- **The summarizer.** It uses the runner's provider plus `extra_config.output_config.effort` `low`, `request_timeout_secs` 20, and a full retry block with no retries. Decide adds 20 s to a flagged turn's timer, staying at or under `MAXTIMER` (110).
- **Usage.** One `Usage` row with agent `compaction` and `Estimated` 1. Input is the prompt plus the flattened transcript, output is the stored summary, both at about 4 characters per token, priced at the summarizer model's rate.
- **Ledger.**
  - DW-125: a history that alone passes the limit answers `too_large` on every turn. Compact it, or rotate to a seeded fresh session.
  - DW-130: show that a four-iteration turn stays under 100,000.
  - DW-93: time `Precheck` at about 100,000 `Usage` rows. If it is slow, index `RecordedAt` (Lane B pins the indexes) or cache the day's spend. Usage rows now go after 90 days.

**30.2 Purge (done; AD-27, AD-23).**

- `Install.Step.Retention` (new Lane A area) declares three tasks, all daily at 03:00 instance time (`DailyStartTime` 10800):
  - `OcuTalon purge heartbeat and check messages`: `messages`, 7 days, `HeartbeatIn,Checks`;
  - `OcuTalon purge Interoperability data`: `all`, 90 days;
  - `OcuTalon purge`: `DaysToKeep` 90.
  
  `StartDate` is today only while today's 03:00 is more than `STARTMARGIN` (300 s) ahead, otherwise tomorrow, because the Task Manager refuses a first start in the past. Its `Purge(days)` calls `Bridge.Purge.Run(days)`.
- `Install.Step.Watch` (new area) only purges: `IncidentManager.Purge(days)`.
- `Bridge.Purge.Run(daysToKeep, now = "")` deletes `Decision` and `Usage` rows older than the cutoff. It deletes an AI session once `^OcuTalonBP.Unlinked(sessionId)` (the first run that found it unlinked) is at least 86,400 s old (veto U-165). It reads the links with one `SELECT` and takes no lock.
- `Bridge.Time.DaysCutoff(daysToKeep, caller, .cutoff, now)` is the shared day check and UTC cutoff, used by `Bridge.Purge` and `Digest.Data.Item.Purge`. `Data.Pairing.Purge` (Lane B) and `IncidentManager.Purge` (Epic 9) keep their copies (DW-371, burndown).
- Not purged: `ApprovalRequest`, `Price`, `ModelFamily`, `BackgroundCheck` and `WatchMark`. DW-437 (Turn, Delivery and Session rows outlive their decisions) waits for a product call.

**30.3 Replay (done; AD-10, AD-11, AD-6, AD-30, AD-31).**

- `ApprovalRequest` gained `ToolSource` and `Runner` (slots 24 and 25, veto U-170). `Approval.Validate` refuses both on a fix row.
- On approval, `Approval.HoldResponse` sends a `tool` request (the Ref in `ItemId`) to Decide. Decide routes it to the row's `Runner` with no precheck, one Decision row of kind `tool` per Ref. An approved row with `ToolSource` or `Runner` empty closes `failed`, with `Decide.HELDBEFOREUPDATE` as the reason (U-170).
- `Bridge.Replay.Run` does the run, in this order:
  1. `StartExecution`, the single gate;
  2. opens a throwaway AI session that is never linked;
  3. `Context.Begin` with the runner, then `Context.Grant(ref)`;
  4. `ExecuteTool` with the stored call;
  5. an Action entry;
  6. `FinishExecution`, which fires `approval.result`.
  
  The gate consumes the grant at the first call whose name, `Context.ArgumentsHash` and source match the row, and denies every other call. `origin_class` arrives on build 154.
- The hold re-arms, retries and delivers. It refuses a start older than 8 s. `Approval.Reconcile` pass 3 starts a hold for:
  - every approved `tool_call` row with no live hold;
  - every approved, rejected or expired fix row with a `ResultTarget`, no live hold, `ExpiresAt` within `DELIVERYDAYS` (7) and no `ApprovalOutcome`.
  
  Fix-test fixtures left in those states get a delivery hold at the next start.
- Routed elsewhere:
  - DW-443 (the next turn's `SystemNote`) and DW-454 (showing U-170's reason) go to Story 31.2;
  - DW-444 (a row left `executing` by a crash) goes to the burndown;
  - DW-451 (the tokenless model GET) is by-design, veto U-172;
  - DW-461 (`Replay.ActionEntry` repeats `Fix.Executor.ActionEntry`'s approver, session and channel fields) is wontfix-accepted. It reopens if a third Action-entry builder appears, or if the identity fields of the two builders diverge, so keep them in step when 30.4 or 30.5 edits the executor's entry.

**30.4 Findings (AD-18, AD-14, AD-30, AD-32, AD-16).**

What exists:

- `Checks.Process` (PoolSize 1) handles each Tick in this order, each step in its own Try/Catch:
  1. the quiet sweep;
  2. `Fixes()`, which sends each final `FixResult` of `Fix.Run.Sweep()` to `IncidentManager`, asynchronously, in the incident's trace session;
  3. the due production checks.
- A run reads through `Watch.Reader.Failures`, which gives the running state: `stopped`, `suspended`, `troubled`, `network_stopped`, `unknown`, `timeout` or running. An item's enabled flag is read only in `Reader.Evidence` (snapshot `items[].enabled`). `Watch.Reader` is the only place that switches namespace (AD-3).
- `Record` writes only the run fields of `BackgroundCheck`, with one SQL `UPDATE` keyed by `Ref`. `LastRunAt` is the clock's `runAt`, while `NextDueAt` follows the Tick time. Findings come from the `FINDING*` parameters.
- No Item is sent today. `BackgroundCheck` has no field that remembers the last reported state, so adding one is a stored-data change.
- `Msg.Catalog.Watch` has `watch.productionStopped` (`production`, `time`) and `watch.itemDisabled` (`itemName`, `production`, `time`).
- `Intake` (Lane B) refuses an Item that is not `untrusted`, has no `ItemId` or `SessionRef`, or has no Text, Subject or Sender. It asks Decide for the attention decision (kind `decide`: Triage, a model request on the mock).
- The executor today:
  - `Executor.Resend` turns `ErrProductionNotRunning` into skip code `stopped` for each copy.
  - `Run` then ends `done` with every target Skipped, so `Watch.Notice.ResultKey` picks `result.skipped`, whose text says the targets had changed since the dry run.
  - `Test.Fix.Runs.TestStoppedProductionSkipsEveryCopy` pins those counts.
- `Executor.CouldNotStart(row, total, reason, saved)` already produces the couldn't-start shape: the row closed `failed`, `Resent`, `Completed`, `FailedAgain` and `Skipped` 0, and the `Reason`. It renders as `result.couldNotStart`. The dependency rule lets Fix read the production's state through `Watch.Reader`.

What to build:

- **The Item.** Each finding becomes one `OcuTalon.Msg.Item` (provenance `untrusted`, owner the check's session) carrying `CatalogKey` and `Slots`, sent to `Intake`. `Intake` copies them to the `ItemDecision`, so `OutcomeRouter`'s notification uses them.
- **Only new.** The last reported state lives in a row. A new `BackgroundCheck` column needs its own veto window.
- **Stopped production at the start of a run** (AD-16 as amended, U-160, DW-368). A target production that is not running when the run starts ends the run as couldn't start: a final `FixResult` with `Resent` 0, `Skipped` 0 and a plain reason, and the row closed `failed`. The new reason sentence is a veto item. The precedents are `UNUSABLE`, `NOREAD` and `NOSTART`.
- **Ledger.** DW-414: `Test.Checks.Runs` TestWindow flaked at an instance midnight (23:59:24Z). It derives its expected `from` from the clock's `LastRunAt`, not from the Tick's own time.

**30.5 Mixed and unfinished (AD-16, AD-15, AD-18).**

What exists:

- `Fix.Executor`'s waiter:
  - One waiter runs at a time, under `WAITLOCK`.
  - `Waiting` lists the runs with `ResentAt` set, no `EndedAt`, not marked, whose row is executing, inside `WAITSECONDS` (60).
  - `Look` ends a run once every copy is done: Skipped is the targets with no copy, and `FailReason` comes from the failed copy with the lowest id.
  - `Pass` drops a run whose time ran out (`LOGWAIT`): nothing is stored or sent, and the row stays `executing`.
- `ResultOf` always sets `Final` 1. There is no in-progress builder.
- `Fix.Run.Sweep()` ends marked runs and DW-395 runs. It leaves alone a run with a copy still running, or whose last copy was done after the wait. That branch is 30.5's, and `Test.Fix.Executor.TestSweepLeavesRunsOfTheWaiterAndOfStory305` pins it.
- `End` and `Mark`, under `RUNLOCK`, are the only writers of a run's end fields.
- `IncidentManager.Result` treats a `FixResult` that is not final and not interrupted as a `progress` event: `fixing` stays `fixing`, and no notice goes out. The notice (`ResultNotice`, with its key from `Notice.ResultKey(row.State, result)`) goes only with a final or interrupted result.
- `Live.Payload.Incident` (Lane A, published by IncidentManager) fills a request's `Result` only from an ended FixRun, so a running request shows no result band on the page today.
- The result key order is already built, identically, in `Watch.Notice.ResultKey` and the page's `resultView` (`web/src/app/approvals/approval-view.ts`), first match wins:
  1. `executing` → `stillResending`;
  2. `Interrupted` > 0 → `interrupted`;
  3. nothing counted and a `Reason` set → `couldNotStart`;
  4. both `FailedAgain` and `Skipped` → `failedAndSkipped`;
  5. `FailedAgain` → `failedAgain`;
  6. `Skipped` → `skipped`;
  7. otherwise `allThrough`.
  
  Every new producer uses it.
- `Executor.Refusal` refuses a past-expiry approved row with an info line. The "past expiry" case of `Test.Fix.Refused` pins "changes nothing". `FinishExecution` accepts `approved` → `failed`.
- `Resend` counts the skip codes `stopped`, `refused` and `error` as Skipped, along with the real changes (`gone`, `status`, `body`, `field`, `changed`).

What to build:

- **When the wait ends with copies running.** Send a `FixResult` with `Final` 0 and the counts so far. The incident stays `fixing`, and the notification uses `result.stillResending`.
- **When every registered copy has completed or failed.** `Sweep` returns the run's one final `FixResult`. `Checks` sends it to `IncidentManager`, which moves the incident by AD-15's table.
- **A mixed result** carries both counts and uses `result.failedAndSkipped`, with the resent, completed, failed-again and skipped counts as slots.
- **Ledger.**
  - DW-384 (U-161): an approved `Execute` whose `ExpiresAt` has passed ends as couldn't start with `NOSTART`, the row closes `failed` through `FinishExecution`, and the incident leaves `fixing`. This is one line in `Executor.Refusal`.
  - DW-419: a resend that errs partway must report the targets it never reached by how far it got, not as `Skipped`. The spine fixes this principle but names no key. A new key or new text is a veto item.

## UX & Interaction Patterns

- **State change:** "The Orders production stopped at {time}." or "The {readable item name} in the Orders production was disabled at {time}.", then "Why now: you asked me to watch the Orders production."
- **Mixed result:** "45 of 50 orders went through. 2 failed again (the order date still wasn't accepted), and 3 had changed since the dry run, so I skipped them. I won't retry any of them without a new approval." When skipped is 1, it reads "so I skipped it."
- **Still running:** "Still resending: 30 of 50 orders have gone through so far. I'll tell you when it's done." When completed is 1: "1 of {count} {item noun} has gone through so far."
- **Couldn't start:** "Nothing was resent: {reason}. Nothing was changed."
- **On the page:** each request card has its own result band, and on the web every result is followed by "Recorded in the IRIS audit log."

## Cross-Story Dependencies

- **Run order:** 30.4, 30.5, then 30.1.
  - 30.1 waits on Epic 9: its live smoke runs in Story 9.5's release-candidate run (three turns across jobs, a compaction, and a tool change with Claude 5.5's thinking-history rule forced). Its other criteria run on the mock.
- **30.4 and 30.5:**
  - Both change `Fix.Executor`'s couldn't-start and skip paths, and both rely on the same result-key order.
  - Both deliver through `Checks` → `IncidentManager`, and both edit `Checks.Process` (the finding Items, and the Sweep results).
  - Their pins in `Test.Fix.Runs`, `Test.Fix.Refused` and `Test.Fix.Executor` change.
- **Contended files:**
  - `Watch/IncidentManager.cls` is shared with Epic 9, which is live. 30.5's in-progress notice and any `DaysCutoff` adoption touch it. `Production.cls` is also Epic 9's.
  - Every existing `Install/**` file is shared with Epic 15. New area files are allowed, as 30.2 showed.
- **30.2 and 30.1:** `Bridge.Purge` removes the AI sessions that compaction and rotation leave behind.
- **Lane B (read only):** `Intake`, `OutcomeRouter`, `Notify`, `Core.BridgeSink`, `Conversation`'s `SystemNote`, `Data.Pairing`, `Data.Time`, `Data.Ownership` and the `Usage` index pin. Stories 31.2 and 13.2 no longer wait on 30.3.
- **Lane A's own:**
  - `src/bridge/**`, `Fix/**`, `Watch/**` (but `IncidentManager.cls`, above) and `Checks/**`;
  - the new Install areas `Install.Step.Retention` and `.Watch`;
  - `Msg/Catalog/Watch.cls`, `Live.Payload.Incident`, `Live.Payload.Check` and the Lane A tables;
  - `ci/mock/scenarios/A/`;
  - `OcuTalon.Test.<Area>`.
