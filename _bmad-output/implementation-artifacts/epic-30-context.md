# Epic 30 Context: Lane A post-demo hardening

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Epic 30 holds the Lane A parts of the demo-path stories that were moved after the demo path: compaction of long conversations, scheduled purges, exactly-once replay of an approved tool call, once-only stopped-production and disabled-item findings, and honest mixed or unfinished resend results. Every part lands before 1.0.0. Stories 30.1 to 30.6 are done. What remains is Story 30.7, a burn-down of the ledger entries the epic still owns. It makes sure old conversations are purged whole, approvals and replays always finish, keys are redacted in every shape, and the tests that flaked now hold.

## Stories

- Story 30.1: Long conversations are compacted under the limit (done)
- Story 30.2: Old messages and records are purged on schedule (done)
- Story 30.3: An approved tool call runs exactly once, with no model (done)
- Story 30.4: A stopped production or a disabled item is reported once (done)
- Story 30.5: Mixed and unfinished resends say how far they got (done)
- Story 30.6: The invalid-reply warning names what failed, never the reply (done)
- Story 30.7: Epic 30 burn-down (backlog)

## Requirements & Constraints

Story 30.7 must resolve these entries. Each kept condition stays exactly as ruled.

- **DW-437, whole-turn purge (veto U-210, kept with two conditions).** Purge `Turn`, `Delivery` and `Session` rows on the same 90-day cut as their `Decision` and `Usage` rows. Today the purge leaves them behind, so `Ownership.TurnCost` reads 0 and `ShownDecisionRef` names a missing decision. One test proves those two never read a purged turn. Each condition below gets its own test beside it:
  1. A `Session` row is purged only when the session has no `Turn`, `Delivery` or `Decision` newer than the cut AND it is not current. Current means signed in, or holding an open approval request, a watch or a reminder. Age alone never qualifies.
  2. The purge touches only OcuTalon's own tables. IRIS audit-log entries for approvals and actions are never purged.
- **DW-444, interrupted replay.** A `tool_call` request left `executing` by a crash or restart must not stay that way. Candidate fix: `Reconcile` at instance start (never from a test's own call) closes such rows through `FinishExecution` with result `interrupted`. The call is still never re-run (NFR-13).
- **DW-470 (U-172's conditions).** A replay that fails because no provider key is set, or because the provider can't be reached, says so in its failed row, in catalog words, and says that nothing was changed. No public text claims a replay works without a provider connection.
- **DW-462, flake.** `OcuTalon.Test.Bridge.Approval` `TestAnswerBeforeTheTaskExists` went red once in CI: the task appeared, `OcuTalonWorkflow` never completed it with Approve, the hold never ended and no single outcome was sent. Find the race and make the test, or the hold, deterministic.
- **DW-386 (U-184).** Extend `OcuTalon.Bridge.Redact` to every shape that `key_like` in `docker/tests/test-boundaries.sh` flags, including DigitalOcean `dop_v1_...` tokens and PEM private-key headers. Also cover `sk-ant-...` keys and Telegram bot tokens (digits, a colon, 35 characters) if `key_like` lacks them. One test per shape, before 1.0.0.
- **DW-448 (U-185).** Make `Test.Eval.KeyProof` `Walk` decode `$List` elements. Then measure on a throwaway whether a message body can store a key in a compressed or split `%Stream.Global*` chunk:
  - If it can, decode those chunks.
  - If it can't, close that half wontfix-accepted, with the evidence: the throwaway build, the message class and what was stored.

  The key proof is otherwise unchanged. Lane B's copy in `Test.Web.SessionEvents` has its own entry.
- **DW-371.** `IncidentManager.Purge` adopts the shared `Bridge.Time.DaysCutoff`, as `Digest` already does. `Data.Pairing.Purge` belongs to Lane B and stays with its own entry.
- **DW-541, only at no date cost.** Chip 1 ("Which productions are running?") gets a real answer. Either `list_productions` returns a code-built running or stopped state for each production (trusted fields only), or, the cheaper option, the chip text becomes "Which productions can you watch?" (the web text plus its `ci/mock/scenarios/B/` scenario). If this would merge the re-open later than Epic 13, the critical path to rc1, move it to the first daily release after 1.0.0.
- **Deferral.** Story 30.7 is built independently of 30.1 and lands in commits of its own. If the rc1 forecast slips past 2026-11-03 18:00Z, the Contest Planner may move it after the tag.

## Technical Decisions

- **Retention.** Day counts are purge-task properties: `OcuTalon.Install.Task.Purge` has `DaysToKeep` 90. The installer writes them only when it creates a task, and no purge reads `OcuTalon.Data.Setting`. That task calls `OcuTalon.Bridge.Purge(daysToKeep)` and then each area's `Purge(daysToKeep)` declaration. History reads OcuTalon's and the bridge's tables, never messages. DW-437 extends this retention rule. Record it in the spine as an amendment marked `[AMENDED <date>, Story 30.7, orchestrator ruling U-210]`. The spine-lint baseline is `ok: false` with 8 low findings, and that must not get worse.
- **Table ownership.** `Turn`, `Delivery` and `Session` belong to Lane B, as do `Ownership` and the `Pairing` purge. `Decision`, `Usage`, `ApprovalRequest` and the other `OcuTalon.Bridge.Data` classes belong to Lane A. `Data/Session.cls` is Epic 31's file: any change to it is one self-contained block appended at its end.
- **Stored data is append-only.** Never rename, retype or remove a stored property, and never hand-edit a `Storage` block. Commit the compiler-generated block. CI diffs every storage block against the last release tag.
- **Approval rows are the truth.** State changes only through the `OcuTalon.Bridge.Approval` API (`Answer`, `Expire`, `Cancel`, `StartExecution`, `FinishExecution`), each under `LOCK ^OcuTalon.Bridge.Approval(Ref)`. `FinishExecution` takes `done`, `failed` or `interrupted`, and `interrupted` leaves the row `failed`. Every change is audited and reported through the HostSink. The startup reconciler re-arms any pending row whose process is gone and cancels orphaned Workflow tasks. A replay runs from the stored row with no model request. The gate consumes the grant on the first match of name, canonical-argument hash and source.
- **Redaction and audit.** `OcuTalon.Bridge.Redact` is the one redactor, used by agent steps, audit, logs and error details. Structural rules come first, and the redactor is the backstop. `OcuTalon.Bridge.Audit` is the only audit writer, and OcuTalon keeps no audit table of its own.
- **Text.** Text a person sees renders from catalog keys. Lane A adds its keys to `OcuTalon.Msg.Catalog.Watch`, and the page's catalog is generated from the catalog classes.
- **Part 1 conventions to keep.** Warnings name IDs, counts and failing properties, go through `Bridge.Redact`, and never quote reply content (30.6). `Bridge.Time.DaysCutoff` is the shared day rule (30.2).

## Cross-Story Dependencies

- Story 30.7 builds on 30.2 (`Bridge.Purge`, `DaysCutoff`, the purge task) and 30.3 (replay, `StartExecution` and `FinishExecution`). Nothing in it depends on 30.1's changes.
- DW-437 changes Lane B tables, and a `Session.cls` edit must not collide with Epic 31's work on that file. DW-541's cheaper option changes web text and a Lane B mock scenario.
- Epic 13 is the critical path to rc1. DW-541 and the deferral of the whole story are both judged against it.
