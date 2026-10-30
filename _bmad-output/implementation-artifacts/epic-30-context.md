# Epic 30 Context: Lane A post-demo hardening

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Epic 30 finishes the Lane A parts of the demo-path stories that the owner moved past the demo path. Each part must land before 1.0.0:

- Long conversations are compacted before their requests near the size limit.
- Old messages and records are purged every day by the standard purge tasks.
- An approved risky tool call runs exactly once, from its stored row, with no model.
- A stopped production or a disabled item reaches the user once.
- A resend that is mixed, still running, stopped partway or unable to start says exactly how far it got, and never claims a change that did not happen.

Each part closes a gap that the demo path left open and that the ledger tracks.

## Stories

- Story 30.1: Long conversations are compacted under the limit
- Story 30.2: Old messages and records are purged on schedule
- Story 30.3: An approved tool call runs exactly once, with no model
- Story 30.4: A stopped production or a disabled item is reported once
- Story 30.5: Mixed and unfinished resends say how far they got

## Requirements & Constraints

- **Request size.** No model request may go over 100,000 input tokens, and a mock conversation long enough to compact must show a largest request under that. The loop bound only holds once every turn flagged above 40,000 tokens is actually compacted: 40,000 + 3 × 10,000 of tool results + 3 × 8,000 of output = 94,000 tokens at Chat's 4 iterations.
- **Retention.**
  - Heartbeat and check messages are kept 7 days.
  - Decisions, incidents, their traces and everything else are kept 90 days by default.
  - Audit entries are never touched; they follow the instance's own audit retention.
  - History reads OcuTalon's and the bridge's tables, never messages, which get purged.
- **Approval before risk.**
  - An approved call runs exactly once, even when the answer or the replay is repeated.
  - Carrying it out calls no model. The mock's request log is the evidence.
  - The caller learns the outcome only as a code-written note (the tool, done or failed, and the time), never the tool's result text.
- **Audit.** The approval entry and the action entry each carry the time, the IRIS user and the session. Tests read them back by polling with a timeout, because IRIS writes some rows late.
- **Only new findings.**
  - The same finding is never sent twice. Two Ticks after a test production stops give exactly one finding Item.
  - What counts as "new" lives in rows, never in memory (AD-5).
- **Honest results.**
  - Each fix run gets exactly one final `FixResult`.
  - Nothing is resent behind the user's back, and a copy that fails again is never retried without a new approval.
  - A result never says "had changed since the dry run" for a target that did not change.
- **Stored data.** Persistent and message classes are append-only (AD-5), with a committed `Storage` block, and the CI storage diff runs against the last tag. Any new column needs its own veto window.
- **Public text.** New public wording is a veto-window item. Text reaches users only as catalog keys and slots, rendered by the `*Out` operations through `Msg.Catalog.Render`.

## Technical Decisions

**30.1 Compaction (AD-20, AD-6, AD-8).**

What exists:

- `Bridge.Process.Decide` estimates the first request: `RequestSize.AgentChars` and `HistoryChars`, plus the input, at `StepBuffer.CHARSPERTOKEN` characters per token.
- On a turn's clone, Decide sets `Request.Compact` to 1 above `COMPACTTOKENS` (40,000), and takes the fallback `too_large` above `RequestTokenLimit` (at most 100,000). The runner (`Operation.AgentRunner` and `Adapter.Agent`) ignores the flag today.
- `Bridge.Compaction` holds `PREFIX` (`OCUTALON-COMPACTION-V1`) and `Prompt()`.
- Mock scenarios `summary.json` and `summary-off-schema.json` exist under `ci/mock/scenarios/A/`. The mock recognises a summarizer request by the prefix at the start of the system text.

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
  - DW-93: time `Precheck` at about 100,000 `Usage` rows. If it is slow, index `RecordedAt` (Lane B pins the indexes) or cache the day's spend.

**30.2 Purge (AD-27, AD-23, AD-2).**

What exists:

- `Install.Task.Purge` ("OcuTalon purge", `DaysToKeep` 90). Its `OnTask` calls `Install.Registry.Purge`, which runs `CallAreas("Purge")` over every `Install.Step.<Area>`.
- `Install.Step.Tasks` creates each declared task once and never touches an existing one.
- Only `Install.Step.Schedule` declares `Tasks()` today: the heartbeat.
- Areas that declare `Purge`: Core (`Data.Pairing`), Digest (`Digest.Data.Item`) and Web (`Live.Event` and `AddressCounter`).
- `Watch.IncidentManager.Purge(daysToKeep)` exists (closed incidents, their groups and their FixRuns), but no area calls it.
- `OcuTalon.Bridge.Purge` does not exist yet.

What to build:

- **Declarations.** A Lane A area's `Tasks()` declares three tasks, all running daily at 03:00 instance time:
  - an `Ens.Util.Tasks.Purge` with `TypesToPurge` `messages`, `NumberOfDaysToKeep` 7, `optionalMessageLimitToConfigItems` set to `HeartbeatIn` and `Checks`, and `BodiesToo`;
  - an `Ens.Util.Tasks.Purge` with `TypesToPurge` `all`, 90 days, `KeepIntegrity` and `BodiesToo`;
  - the OcuTalon purge task.
- **Task rules.** Task names start with `OcuTalon`. Day counts are task properties written only when the task is created, so no purge reads `Data.Setting`. A second start still leaves one task of each.
- **`Bridge.Purge(daysToKeep)`.** It keeps decisions and usage for N days, and deletes AI sessions that no `ConversationLink` has pointed to for a day (left behind by compaction and rotation). `Install.Task.Purge` calls it directly. The bridge must not reference OcuTalon packages, so it uses `Bridge.Time`.
- **Ledger.** DW-371 wants one shared day-count check and UTC cutoff in place of copies. `Data.Pairing` and `Data.Time` are Lane B's, and the bridge cannot share OcuTalon code.

**30.3 Replay (AD-10, AD-11, AD-6, AD-30, AD-31).**

What exists:

- `Policy.Gate` holds a risky or unclassified call through `Approval.Raise` and denies it with `HELD`. The raised request is kind `tool_call`, with `ToolName`, `ToolArguments` as given, `OwnerRef`, `TraceRef` and no `ResultTarget`.
- `Approval.HoldResponse` sends nothing for an approved `tool_call`.
- Decide answers kind `tool` with "not implemented", and `RUNNERS` maps only `decide`, `diagnose` and `turn`.
- `Approval.StartExecution` and `FinishExecution` exist. `StartExecution` needs an approved row whose `ExpiresAt` is still ahead. `FinishExecution` fires `approval.result` to the HostSink.
- `ApprovalRequest` has no column for the tool's source class or for the runner item that made the call (DW-194).

What to build:

- **The path.** `ApprovalHold` sends a `tool` request carrying the `Ref`, through Decide, to the runner of the agent that made the call. That runner:
  1. calls `StartExecution`;
  2. sets the context: provenance `user`, the `Ref` and a process-private grant;
  3. calls `..Agent.ToolManager.ExecuteTool`, which takes the call through the whole policy chain;
  4. records `FinishExecution`.

  The `tool` kind uses a throwaway, unlinked session and gets its own `Decision` row of kind `tool`.
- **The gate.** Before rule 4 it checks for a live grant, and consumes it at the first call whose name, hash of canonical arguments (sorted keys) and source match the row. With no live grant the gate denies, and `ExecuteTool` raises `ToolAccessDenied`. The gate's only rewrites are the `top_k` clamp and MCP routing.
- **Open check.** Confirm whether `metadata.origin_class` arrives on a replay on build 154. If it doesn't, the source comes from the row.
- **The hold.** `ApprovalHold`'s persistent properties are frozen; logic stays in `Approval`.
- **Ledger.**
  - DW-192: Reconcile or the hold delivers an answered or expired row that has no live hold, including the expired outcome to `ResultTarget`.
  - DW-194: add the source and runner fields, or derive them.
  - DW-195: measure `ApprovalStartIn` held past `STARTSECONDS` (10), and re-check the row before the hold sends its task.
  - DW-99: this story turns on the real `approval.result`.

**30.4 Findings (AD-18, AD-14, AD-30, AD-32, AD-16).**

What exists:

- `Checks.Process` (PoolSize 1) handles each Tick in this order: the quiet sweep, the results of `Fix.Run.Sweep()`, then the due production checks.
- It reads through `Watch.Reader.Failures`, which gives the running state. `Watch.Reader` is the only place that switches namespace (AD-3). Today an item's enabled flag is read only in `Reader.Evidence`.
- It writes only the run fields of `BackgroundCheck`, with one SQL `UPDATE` keyed by `Ref`, and its findings come from its `FINDING*` parameters.
- It sends no Item today, and `BackgroundCheck` has no field that remembers the last reported state.
- `Msg.Catalog.Watch` has `watch.productionStopped` (`production`, `time`) and `watch.itemDisabled` (`itemName`, `production`, `time`).

What to build:

- **The Item.** Each finding becomes one `OcuTalon.Msg.Item` (provenance `untrusted`, owner the check's session) carrying `CatalogKey` and `Slots`, sent to Lane B's `Intake`. `Intake` already copies them to the `ItemDecision`, so the notification from `OutcomeRouter` uses them.
- **Stopped production at the start of a run** (AD-16 as amended, U-160 and DW-368). A target production that is not running when the run starts ends the run as couldn't start: a final `FixResult` with `Resent` 0, `Skipped` 0 and a plain reason, and the row closed `failed`. Today `Executor.Resend` counts `ErrProductionNotRunning` per copy as skipped, and `Test.Fix.Runs.TestStoppedProductionSkipsEveryCopy` pins those old counts.
- **Ledger.** DW-414: `Test.Checks.Runs` TestWindow reads the real clock near midnight; it should use the Tick's own time.

**30.5 Mixed and unfinished (AD-16, AD-15, AD-18).**

What exists:

- `Fix.Executor`'s waiter waits up to `WAITSECONDS` (60) from `ResentAt`. A run whose copies are not done by then logs `LOGWAIT`, stores and sends nothing, and stays `executing`.
- `Fix.Run.Sweep()` ends marked runs and DW-395 runs, but leaves alone a run with a copy still running or with its last copy done after the wait. That branch is 30.5's.
- `End` and `Mark`, under `RUNLOCK`, are the only writers of a run's end fields.
- `ResultOf` sets `Final` 1.
- `NOSTART` is "OcuTalon couldn't start the resend".
- `Refusal(row)` refuses a past-expiry row with an info line.

What to build:

- **When the wait ends with copies running.** Send a `FixResult` with `Final` 0 and the counts so far. The incident stays `fixing`, and the notification uses `result.stillResending`.
- **When every registered copy has completed or failed.** `Sweep` returns the run's one final `FixResult`. `Checks` sends it to `IncidentManager`, which moves the incident by AD-15's table.
- **A mixed result** carries both counts and uses `result.failedAndSkipped`, with the resent, completed, failed-again and skipped counts as slots.
- **Result key order.** Every producer, the page included, picks the key from the same fields in this order, first match wins:
  1. `executing` → `stillResending`;
  2. `Interrupted` > 0 → `interrupted`;
  3. nothing counted and a `Reason` set → `couldNotStart`;
  4. both `FailedAgain` and `Skipped` → `failedAndSkipped`;
  5. `FailedAgain` → `failedAgain`;
  6. `Skipped` → `skipped`;
  7. otherwise `allThrough`.
- **Ledger.**
  - DW-384 (U-161): an approved `Execute` whose `ExpiresAt` has passed ends as couldn't start with `NOSTART`, the row closes `failed` through `FinishExecution`, and the incident leaves `fixing`.
  - DW-419: a resend that errs partway must report the targets it never reached by how far it got, not as `Skipped`. The spine fixes this principle but names no key; a new key or new text is a veto item.

## UX & Interaction Patterns

- **State change:** "The Orders production stopped at {time}." or "The {readable item name} in the Orders production was disabled at {time}.", then "Why now: you asked me to watch the Orders production."
- **Mixed result:** "45 of 50 orders went through. 2 failed again (the order date still wasn't accepted), and 3 had changed since the dry run, so I skipped them. I won't retry any of them without a new approval." When skipped is 1, it reads "so I skipped it."
- **Still running:** "Still resending: 30 of 50 orders have gone through so far. I'll tell you when it's done." When completed is 1: "1 of {count} {item noun} has gone through so far."
- **Couldn't start:** "Nothing was resent: {reason}. Nothing was changed."
- **On the page:** each request card has its own result band, and on the web every result is followed by "Recorded in the IRIS audit log."
- **Tool-call card:** "No dry run is available for this tool. Approving runs exactly this call once."

## Cross-Story Dependencies

- **Run order:** 30.2, 30.3, 30.4, 30.5, then 30.1.
  - 30.1's live smoke runs in Epic 9's release-candidate run (Story 9.5): three turns across jobs, a compaction, and a tool change with Claude 5.5's thinking-history rule forced. Its other criteria run on the mock.
- **30.2 and 30.1:** `Bridge.Purge` removes the AI sessions that compaction and rotation leave behind.
- **30.4 and 30.5:** both change `Fix.Executor`'s couldn't-start and skip paths, and both rely on the same result-key order. Both deliver through `Checks` → `IncidentManager`, and both edit `Checks.Process` (the finding Items, and the Sweep results).
- **Lane B (read only):** `Intake`, `OutcomeRouter`, `Notify`, `Core.BridgeSink`, `Conversation`'s `SystemNote`, `Data.Pairing`, `Data.Time` and the `Usage` index pin. Story 31.2 (tool-call notifications) and Story 13.2 wait for 30.3.
- **Lane A's own:**
  - `src/bridge/**`, `Fix/**`, `Watch/**` and `Checks/**`;
  - the installer core (`Install.Step.Tasks`, `Install.Task.Purge`, the Lane A areas);
  - `Msg/Catalog/Watch.cls` and the Lane A tables;
  - `ci/mock/scenarios/A/`;
  - `OcuTalon.Test.<Area>`.
