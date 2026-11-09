# Epic 30 Context: Lane A post-demo hardening

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Finish the Lane A parts that were moved off the demo path so they land before release: long conversations are compacted under the request-size limit, old messages and records are purged on schedule, an approved tool call is replayed exactly once with no model, a stopped production or disabled item is reported once, mixed or unfinished resends say how far they got, refused replies never leak model text into the trace, and every key shape is redacted. Stories 30.1 to 30.6, 30.8 and 30.9 are done. Story 30.7 (the epic's burn-down) was deferred after v1.0.0 and was RE-OPENED on 2026-11-08 (SC-5, the Contest Planner under the owner's delegation; runner B, slot B). It is built now and merged after the 1.0.4 cut, and the owner's answers U-210, U-214 and U-215 apply. The note in Story 30.9 that 30.7 "stays deferred" is superseded by this re-open.

## Stories

- Story 30.1: Long conversations are compacted under the limit
- Story 30.2: Old messages and records are purged on schedule
- Story 30.3: An approved tool call runs exactly once, with no model
- Story 30.4: A stopped production or a disabled item is reported once
- Story 30.5: Mixed and unfinished resends say how far they got
- Story 30.6: The invalid-reply warning names what failed, never the reply
- Story 30.7: Epic 30 burn-down (re-opened 2026-11-08)
- Story 30.8: The redactor and the key proof catch every key shape
- Story 30.9: A 'Remember that ...' chat message gets a usable attention decision

## Requirements & Constraints

- **No risky action without approval, and exactly once (NFR-13).** An approved call runs once even when the answer or the replay is repeated. A row left `executing` by a crash is never re-run.
- **Retention (NFR-19).** Heartbeat and check messages are kept 7 days. Decisions, incidents and traces are kept 90 days by default. Audit entries follow the instance's own audit retention and are never purged by OcuTalon.
- **Requests stay under 100,000 tokens (NFR-3).**
- **User-facing failure text is plain English in catalog words.** It never contains a class name, an error code or tool result text, and it never claims a change that did not happen.
- **What is left in Story 30.7** (each item with the kept condition it carries):
  - **DW-437, turn records outliving their decisions.** Purge `Turn`, `Delivery` and `Session` rows on the same 90-day cut as their `Decision` and `Usage` rows (U-210, kept with two conditions).
    - (1) A `Session` row is purged only when it has no Turn, Delivery or Decision newer than the cut AND it is not current (signed in, or with an open approval request, watch or reminder). It is never purged by age alone.
    - (2) Only OcuTalon's own tables are purged. The IRIS audit log is never touched.
    - Tests: one shows that `TurnCost` and `ShownDecisionRef` never read a purged turn, and one test per condition sits beside it.
  - **DW-444, rows stuck in `executing`.** At instance start (never on a test's call), Reconcile closes a `tool_call` row left `executing` through `FinishExecution` with result `interrupted`.
  - **DW-470, replay failures say what failed (U-172, amended by the owner's U-214 condition).** The failed row's sentence names what actually failed. The story's test names which endpoint it checks, and the wording follows that endpoint:
    - Model provider unreachable (for example the AI Hub provider object or its key): "The model provider could not be reached, so the approved call did not run. Nothing was changed."
    - The tool's own server unreachable (an MCP server or tool set): "The tool's server could not be reached, so the approved call did not run. Nothing was changed."
    - No key set: U-170's existing `no_key` wording plus "Nothing was changed."
    - No public text may claim that a replay works without a provider connection.
  - **DW-462, a flaky approval test.** `OcuTalon.Test.Bridge.Approval` TestAnswerBeforeTheTaskExists failed once in CI. Find the race and make the test, or the hold, deterministic.
  - **DW-584, keys for a several-ref `cancel_reminder` (owner decision U-215, kept).** One test pins that the IdempotencyKeys of one tool call (`:2`, `:3`, `:4`) are each accepted once and refused on a repeat. The AD-1 wording stays as built and carries its marker and lint. No code change.
  - **DW-371, the purge day rule.** `IncidentManager.Purge` uses the shared `Bridge.Time.DaysCutoff`, as Digest does. `Data.Pairing.Purge` belongs to Lane B and stays with its own ledger entry.
  - **DW-541, chip 1.** Either `list_productions` returns a running or stopped state for each production, built by code from trusted fields only, or the chip text becomes "Which productions can you watch?" (the web text and its `ci/mock/scenarios/B/` scenario). Do this only if it costs no date. Otherwise it moves to the first daily release after 1.0.0.
  - **Already handled:** Story 30.8 delivered DW-386 and DW-448. The set-aside patch from 2026-11-02 no longer applies to the current head; use it as reference only.

## Technical Decisions

- **AD-1 (idempotency key, U-215 marker of 2026-11-08):**
  - A tool's command carries `IdempotencyKey`: the turn's `ItemId` plus the command's position in the turn, so each command of a several-command tool call gets its own key.
  - A replay runs the stored `ToolName` and `ToolArguments` in a context whose `ItemId` is the approval `Ref`. The positions are therefore the same on every replay, and the replay gate keeps the call to exactly once.
  - The command's owner ignores a repeated key.
- **AD-10/AD-11 (replay):**
  - `ApprovalHold` sends a `tool` request carrying the `Ref` through `Decide` to the runner that made the call.
  - The runner calls `StartExecution`, sets a context (provenance `user`) and a process-private grant, calls `ExecuteTool` through the full policy chain, then records `FinishExecution`.
  - The gate consumes the grant on the first matching call (name, hash of the canonical arguments with sorted keys, and source). It denies a call with no live grant (`ToolAccessDenied`).
  - Row states change only through the Approval API, under `LOCK ^OcuTalon.Bridge.Approval(Ref)`.
  - `FinishExecution` with `interrupted` leaves the row `failed`. Every change is audited (AD-17) and reported through the HostSink (`approval.result`).
- **AD-27 (retention):**
  - Two standard `Ens.Util.Tasks.Purge` tasks plus `OcuTalon.Install.Task.Purge` (`DaysToKeep` 90), all run daily at 03:00.
  - The task calls `OcuTalon.Bridge.Purge(daysToKeep)` and each area's `Purge(daysToKeep)` declaration.
  - Day counts are task properties, written only when each task is created. No purge reads `OcuTalon.Data.Setting`.
  - DW-437 extends this decision. Story 30.7 adds the marker `[AMENDED <date>, Story 30.7, orchestrator ruling U-210]`. The spine lint baseline is `ok: false` with 8 low findings.
- **AD-8 (fallback reasons):** `Decide` alone classifies a reply as unusable, with reasons such as `no_key` and `error`. Every provider failure arrives as `<%AICore>ProviderError` and is classified by its text in one method.
- **AD-20 (compaction):** turns above 40,000 tokens are compacted through `ForkAndSummarize`. `Summarize` in place is never used. The summarizer's cost is recorded as an `Estimated` `compaction` usage row. The ownership API's `TurnCost` sums the turn's decision rows and stores no total.
- **AD-33 and lane rules:** only the owning lane edits a class. `Data/Session.cls` belongs to Epic 31. A change there must be one self-contained block appended at the end of the file.
- **Conventions:**
  - Errors use `%Status` throughout.
  - One redactor, `OcuTalon.Bridge.Redact`.
  - Text sent to people is rendered only from the `OcuTalon.Msg.Catalog.*` classes, through `Catalog.Render`.
  - Test classes are named `OcuTalon.Test.<Area>.<Subject>`.
  - Audit entries are written only through `Bridge.Audit.Record`.

## UX & Interaction Patterns

- The tool-call approval card says: "No dry run is available for this tool. Approving runs exactly this call once." After a replay, the caller's next turn carries a code-written note giving the tool, done or failed, and the time. It never includes the tool's result text.
- A failed replay reads in the catalog's plain words and always ends "Nothing was changed."

## Cross-Story Dependencies

- Story 30.7 is built independently of 30.1. It lands in commits of its own and merges after the 1.0.4 cut.
- Story 30.7 builds on what is already done:
  - Story 30.2's purge task and `Bridge.Time.DaysCutoff`.
  - Story 30.3's replay, `approval.result`, and the U-170 failed-row wording.
  - Story 30.8's redactor and key-proof work.
- Story 31.2 (Lane B) depends on Story 30.3's `approval.result`. `Data/Session.cls` and `Data.Pairing.Purge` stay Lane B's.
