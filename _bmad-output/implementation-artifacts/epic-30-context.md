# Epic 30 Context: Lane A post-demo hardening

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Epic 30 finishes the Lane A parts of the demo-path stories that the owner moved past the demo path, and each part lands before 1.0.0. Long conversations are compacted before their requests near the size limit. Old records are purged on schedule. An approved tool call replays exactly once with no model. A stopped production or a disabled item reaches the user once. A resend that is mixed, still running or stopped partway says exactly how far it got and never claims a change that did not happen. Stories 30.2, 30.3 and 30.4 are done. Epic 9 has merged, so 30.1 and 30.5 are both unblocked, and the epic's burn-down story comes after them.

## Stories

- Story 30.1: Long conversations are compacted under the limit
- Story 30.2: Old messages and records are purged on schedule (done)
- Story 30.3: An approved tool call runs exactly once, with no model (done)
- Story 30.4: A stopped production or a disabled item is reported once (done)
- Story 30.5: Mixed and unfinished resends say how far they got
- Epic 30 burn-down (chartered by the burn-down gate)

## Requirements & Constraints

- **Request size.** No model request may go over 100,000 input tokens. A mock conversation long enough to compact must record a largest request under that. The loop bound holds only once every turn flagged above 40,000 tokens is actually compacted: 40,000 + 3 × 10,000 of tool results + 3 × 8,000 of output = 94,000 at Chat's 4 iterations.
- **No key leaks.** The product redactor replaces every key shape that CI's key-like scanner flags. The release candidate's key proof must not read a stored key as clean.
- **Honest results.**
  - Each fix run gets exactly one final `FixResult`, and at most one in-progress result.
  - Nothing is resent behind the user's back, and a copy that fails again is never retried without a new approval.
  - A result never claims a change that did not happen: "had changed since the dry run" is only for a target that really changed.
  - A result never reads all-through while a target was left out.
- **Exactly once (built; keep it).**
  - An approved call runs once and makes no inference request. The one tokenless model-metadata GET is allowed (U-172).
  - It reports only through the row and `approval.result` (`{"ref"}`), never through the tool's result text.
- **Retention (built; keep it).** `Bridge.Purge` deletes an AI session one day after no conversation link names it. That works only while the runner is the only code that saves AI sessions and points the link right after the save, so the compaction fork must keep that true.
- **Audit.** Approval and Action entries are written only through `Bridge.Audit`, each with the time, the IRIS user and the session. Tests read them back by polling with a timeout.
- **Stored data.** Persistent and message classes are append-only, with a committed `Storage` block and the compiler's new slots written back verbatim. Each new column is its own veto item and gets our own entry in `Test.Data.Tables`.
- **Public text.**
  - Every new reason sentence, key or text is a veto item.
  - Producers never render: users see text only as catalog keys and slots, rendered by the `*Out` operations through `Msg.Catalog.Render`.
  - Time slots are UTC.
- **Where tests run.** Tests run on throwaway stacks only; the dev slot is for load and compile only. The repository is public, so fixtures use the existing fixture names only.

## Technical Decisions

**30.1 Compaction (AD-20, AD-6, AD-8).**

- **What exists.**
  - `Decide` estimates the first request (`RequestSize`, `StepBuffer.CHARSPERTOKEN`). It sets `Request.Compact` above `COMPACTTOKENS` (40,000) and takes the `too_large` fallback above `RequestTokenLimit`. The runner ignores the flag today.
  - A linked turn runs through `AnswerLinked`: the link lock, then `OpenSession` or `NewSession`, then `Converse` (`Chat`), then `SaveLinked` (`%Save`, then `ConversationLink.Point`).
  - `Bridge.Compaction` holds `PREFIX` and `Prompt()`. The mock scenarios `A/summary.json` and `A/summary-off-schema.json` exist.
  - The code-rule pins are `CHATTERS` (AgentRunner, Adapter.Agent), `SESSIONMAKERS` (Adapter.Agent) and `LINKNAMERS`. A compaction class outside the adapter must be added to them on purpose.
- **Where it runs.** The runner compacts in its own job, outside every callback, before `Chat`. No callback may call AI Hub's native library, because that deadlocks.
- **The call.** `ForkAndSummarize(summarizerProvider, "", k, prompt, 0)`. `k` keeps the last user turn whole and comes from `GetContext()`. With no older history there is no compaction. `Summarize` in place is never used.
- **The switch.** The link moves to the fork only after the check passes: the first non-system message is a user message, and every tool result follows its call. Then the runner `%Save`s the fork.
- **The fallback.** An exception (`<%AICore>InternalError`) or a failed check gives a fresh AI session, seeded with a code-written summary of the stored user and assistant texts. A compaction failure is never the turn's `FallbackReason`.
- **The summarizer.** It uses the runner's provider plus `extra_config.output_config.effort` `low`, `request_timeout_secs` 20 and no retries. `Decide` adds 20 s to a flagged turn's timer, staying at or under `MAXTIMER` (110).
- **Usage.** One row, with agent `compaction` and `Estimated` 1. Input is the prompt plus the flattened transcript, output is the stored summary, both at about 4 characters a token, priced at the summarizer model's rate.
- **The live smoke test.** It runs in release-candidate runs on the real model: three turns across jobs, a compaction and a tool change, with the thinking-history rule forced. Until 30.1 wires it into Epic 9's run, the result's `thinkingHistorySmoke` reads "not run" (`Eval.Gate.SMOKE`, and the note in `eval/run.sh`).
- **Ledger.**
  - **DW-125:** a history that alone passes the limit answers `too_large` on every turn. Compact it, or rotate to a seeded fresh session.
  - **DW-130:** show that a four-iteration turn stays under 100,000.
  - **DW-93:** time `Precheck` at about 100,000 `Usage` rows. If it is slow, index `RecordedAt` (Lane B pins the indexes) or cache the day's spend.
  - **DW-386 (U-184):**
    - `Bridge.Redact` must cover every pattern of `key_like` in `docker/tests/lib-keys.sh`, the one definition that `test-boundaries.sh` and `eval/run.sh` read, with one test per shape.
    - Missing today: DigitalOcean `dop_v1_` tokens and PEM private-key headers.
    - `sk-ant-` and the Telegram bot token are already in `key_like` and in Redact, but each still gets its test (the owner's condition).
    - Redact stays idempotent, never throws, fails closed and names no OcuTalon package (AD-2).
  - **DW-448 (U-185):**
    - `Test.Eval.KeyProof`'s `Walk` decodes `$List` elements.
    - On a throwaway, measure whether a message body can store a key in a compressed `%Stream.Global*` chunk (blocks of 1 KB or more compress) or in a chunk split across nodes. If it can, decode those too. If it can't, that half closes wontfix-accepted, and the ledger entry gets the evidence: the throwaway's build, the message class and what was stored.
    - The key proof otherwise stays as it is. Lane B's copy, `Test.Web.SessionEvents.ReferenceHits`, is DW-474 in Story 31.4, so don't edit it.

**30.5 Mixed and unfinished (AD-16, AD-15, AD-18).**

A planned spec exists (ready-for-dev, not validated). It was written before Epic 9 merged, so the spec gate must apply these rulings:

- **Q1 (orchestrator).** `Watch/IncidentManager.cls` is now Lane A's and uncontended. The one-line edit in `Result` (call `ResultNotice` for every result, not only a final one) is allowed. There is no split and no Story 30.6.
- **U-182 (kept): AD-16 is extended.**
  - The extension:
    - `FixResult` gains `Unreached`.
    - A resend stops at the first copy that errs (`stopped`, `refused` or `error`).
    - A run where no copy went ends as couldn't start: `NOTRUNNING` for a stop, otherwise `NOSTART`. A throw before any copy stays `NOREAD`.
    - `result.stoppedPartway` joins the Result texts order right after `couldNotStart`.
  - It is written into the spine with the orchestrator's marker and the spine lint, whose baseline is 8 low findings.
  - **The owner's condition:** the stoppedPartway text gives three counts (resent, the copy that erred, and not tried) and says that nothing else was changed, and a test pins a run that stops at copy k of n. The planned text ("The other {remaining} need a new approval") does not meet this.
- **U-183 (kept).**
  - 30.5 adds `unreached` to `Live.Payload.Incident` (Lane A, its publisher), and `result.stoppedPartway` with its count-of-one form to the Watch catalog class. The chat notice uses it.
  - Two parts go to Lane B's Story 31.2 (DW-472, DW-473): the page's pick in `resultView` with the web key lists, and a still-resending band. 30.5 makes no `web/` edit.
  - The spec's Never-list entry that calls `Live.Payload.*` Lane B is out of date.
- **V1 (still a veto item at the spec gate).** The stored column `FixRun.Unreached`, written with `ResentAt`, because the waiter and `Sweep` end runs later, in other jobs.

What the code does today:

- **The waiter.** It runs under `WAITLOCK` and waits `WAITSECONDS` (60). When the time runs out, `Pass` logs `LOGWAIT`, stores and sends nothing, and leaves the row `executing`.
- **`ResultOf`** always sets `Final` 1.
- **`Sweep`** leaves alone a run whose last copy finished after the wait. `Test.Fix.Executor.TestSweepLeavesRunsOfTheWaiterAndOfStory305` pins that.
- **`End` and `Mark`,** under `RUNLOCK`, are the only writers of a run's end.
- **`IncidentManager.Result`** treats a result that is neither final nor interrupted as progress: `fixing` stays `fixing`, and no notice goes out yet.
- **DW-384.** `Executor.Refusal` refuses a past-expiry approved row with an info line. The fix is couldn't start with `NOSTART`, through `CouldNotStart`, with `FinishExecution` moving the row from approved to failed.
- **DW-419.** `Resend` counts `stopped`, `refused` and `error` as Skipped. 30.4's review routed one occurrence here: a start read that times out on a stopped production.

The result key order:

- `Watch.Notice.ResultKey` and the page's `resultView` use the same order, and the first match wins:
  1. `executing` gives `stillResending`;
  2. `Interrupted` above 0 gives `interrupted`;
  3. nothing counted and a `Reason` set gives `couldNotStart`;
  4. (new) `Unreached` above 0 gives `stoppedPartway`;
  5. both failed again and skipped give `failedAndSkipped`;
  6. failed again gives `failedAgain`;
  7. skipped gives `skipped`;
  8. otherwise `allThrough`.
- Every producer uses this order. The plan also maps any result that is neither final nor interrupted to `stillResending`, and the mixed result's slots gain `resent`.

**DW-469 (U-180's condition).** Pin with a test that the `{time}` of `watch.productionStopped` and `watch.itemDisabled` renders through the catalog's time format with the zone label (ET on the online demo), for both sources: IRIS's stop time and the check's detection time.

**Keep consistent with the done stories.**

- **30.4.**
  - `Checks` writes `BackgroundCheck.Reported` in its single `UPDATE` keyed by `Ref`. A row's first reading run is a baseline, and `Reported` holds only current conditions.
  - A finding Item is `untrusted`, goes to `Intake` only, and travels in a trace session of its own, with the owner's TraceRef as SuperSession (AD-26).
  - The executor checks the target's state through `Watch.Reader` after `StartExecution` and the FixRun's save. `stopped`, `suspended` and `network_stopped` end the run as couldn't start with `NOTRUNNING`.
  - A stop after that check is 30.5's.
- **30.3.**
  - `ApprovalRequest` holds `ToolSource` and `Runner`.
  - The replay's first `ExecuteTool` makes one tokenless `GET /v1/models/<model>`. `BuildAgent` needs a provider key: without one, the row closes `failed` (`ProviderCreateFailed`) with no reason the person reads.
  - The bridge cannot name the host catalog (AD-2), so U-170's sentence went into the Decision row's `Reasons` through a `Decide` parameter (`HELDBEFOREUPDATE`).
  - DW-461 reopens if the identity fields drift, so keep `Replay.ActionEntry`'s and `Fix.Executor.ActionEntry`'s approver, session and channel fields in step if 30.5 edits the executor's entry.
- **30.2.** `Bridge.Time.DaysCutoff` is the shared day-count check and UTC cutoff.

**Burn-down candidates** (the ledger routes these to `burndown` and marks them for Epic 30; the gate fixes the list):

- **DW-470 (U-172).** A replay that fails for lack of a provider key, or because the provider can't be reached, says so in its failed row in catalog words, and says that nothing was changed. No public text may claim that a replay works offline.
- **DW-444.** A `tool_call` row that a crash leaves `executing` mid-replay stays that way. The candidate fix: a start-only `Reconcile` path (never the one tests call) closes it through `FinishExecution` as interrupted.
- **DW-462 (priority flake).** `Test.Bridge.Approval.TestAnswerBeforeTheTaskExists` went red once on CI. The likely cause is the hold's timing under 30.3's re-arm and retry.
- **DW-371 (what's left).** `IncidentManager.Purge`'s copy of the day check, now in a Lane A file, can adopt `DaysCutoff`. `Data.Pairing.Purge` is Lane B's.
- **DW-437.** Still waiting for a product call: Turn, Delivery and Session rows outlive their purged Decision and Usage rows.

## UX & Interaction Patterns

- **Mixed:** "45 of 50 orders went through. 2 failed again (the order date still wasn't accepted), and 3 had changed since the dry run, so I skipped them. I won't retry any of them without a new approval."
- **Still running:** "Still resending: 30 of 50 orders have gone through so far. I'll tell you when it's done." With one completed: "1 of {count} {item noun} has gone through so far."
- **Cut off by a restart:** "The resend stopped when OcuTalon restarted: 30 of 50 orders went through. The other 20 need a new approval." `stoppedPartway` follows this shape, but it must not borrow the restart cause.
- **Couldn't start:** "Nothing was resent: {reason}. Nothing was changed." The two reasons are `NOTRUNNING` ("the production isn't running") and `NOSTART` ("OcuTalon couldn't start the resend").
- **On the page:** each request card has its own result band, and on the web every result is followed by "Recorded in the IRIS audit log."

## Cross-Story Dependencies

- **30.1 and Epic 9 (merged):**
  - Story 9.5's release-candidate run carries 30.1's live smoke test.
  - `Eval/**` and `Test/Eval/**` are now Lane A files this epic may edit.
- **30.1 and 30.2:** `Bridge.Purge` removes the AI sessions that a fork or a rotation leaves behind, so 30.1 adds no cleanup.
- **30.5 and Lane B:**
  - Story 31.2 takes the page's stopped-partway pick (first, if 31.2 splits), the still-resending band, and DW-443 and DW-454 (the next turn's note, and showing U-170's reason).
  - Until then, the page shows a partway run in the old wording.
- **30.5 and Epic 12:** Telegram's in-place result edit sees a progress notice, then the final notice, with the same ApprovalRef.
- **Lane A's own files:**
  - `src/bridge/**`, `Fix/**`, `Watch/**` (with `IncidentManager.cls`), `Checks/**`, `Eval/**` and `Test/Eval/**`;
  - `Msg/Catalog/Watch.cls`, `Live.Payload.Incident`, `Live.Payload.Check` and the Lane A tables;
  - the new Install areas `Install.Step.Retention` and `.Watch`;
  - `ci/mock/scenarios/A/` and `OcuTalon.Test.<Area>`.
- **Shared files:**
  - Existing `Install/**` files are shared with Epic 15; new area files are allowed.
  - `Test/Data/Tables.cls` is shared by entry.
- **Lane B (read only):** `Intake`, `OutcomeRouter`, `Notify`, `Core.BridgeSink`, `Conversation`, `Data.Pairing`, `Data.Time`, `Data.Ownership`, `web/**` and the `Usage` index pin.
