# Epic 30 Context: Lane A post-demo hardening

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Epic 30 finishes the Lane A parts of the demo-path stories that the owner moved past the demo path, and each part lands before 1.0.0, the first release (no 0.1.x is cut). Long conversations are compacted before their requests near the size limit. Old records are purged on schedule. An approved tool call replays exactly once with no model. A stopped production or a disabled item reaches the user once. A resend that is mixed, still running or stopped partway says exactly how far it got and never claims a change that did not happen. A new story, 30.6, runs first: the trace warning for a refused model reply names what failed and never quotes the reply, so the model's own text cannot reach the event log through it. Stories 30.2, 30.3 and 30.4 are done. 30.1 and 30.5 have planned specs that are not validated yet, and the burn-down story (30.7) comes last.

## Stories

- Story 30.1: Long conversations are compacted under the limit
- Story 30.2: Old messages and records are purged on schedule (done)
- Story 30.3: An approved tool call runs exactly once, with no model (done)
- Story 30.4: A stopped production or a disabled item is reported once (done)
- Story 30.5: Mixed and unfinished resends say how far they got
- Story 30.6: The invalid-reply warning names what failed, never the reply (new; runs first)
- Then the burn-down story (30.7), if the burn-down gate charters one

## Requirements & Constraints

- **No reply content in warnings (30.6, U-193).** A warning about a refused reply quotes none of the reply's values: not even redacted, and not even in part.
- **Request size.** No model request may go over 100,000 input tokens. A mock conversation long enough to compact must record a largest request under that. The bound (40,000 + 3 × 10,000 of tool results + 3 × 8,000 of output = 94,000 at Chat's 4 iterations) holds only once every turn flagged above 40,000 is compacted.
- **No key leaks.** The product redactor must cover every key shape that CI's key-like scanner flags, and the key proof must not read a stored key as clean.
- **Honest results.**
  - Each fix run gets exactly one final `FixResult`, and at most one in-progress result.
  - Nothing is resent behind the user's back. A copy that fails again is never retried without a new approval.
  - "Had changed since the dry run" is only for a target that really changed. A result never reads all-through while a target was left out.
- **Exactly once (built; keep it).** An approved call runs once and makes no inference request. The one tokenless model-metadata GET is allowed (U-172). It reports only through the row and `approval.result` (`{"ref"}`).
- **Retention (built; keep it).** `Bridge.Purge` deletes an AI session one day after no conversation link names it. That works only while the runner is the only code that saves AI sessions and points the link right after the save, so the compaction fork must keep that true.
- **Audit.** Approval and Action entries are written only through `Bridge.Audit`, each with the time, the IRIS user and the session. Tests read them back by polling with a timeout.
- **Stored data.**
  - Persistent and message classes are append-only, with a committed `Storage` block and the compiler's new slots written back verbatim.
  - Each new column is its own veto item and gets our own entry in `Test.Data.Tables`.
  - Epic 9's eval tests pin stored fields. 30.4's `BackgroundCheck.Reported` turned CI red until it joined `Watch.Ops` `FIELDS` (fixed in 8cf26aa8), so check any new column against `Test.Eval.*`.
- **Public text.** Every new reason sentence, key, prompt wording or text is a veto item. Producers never render: users see text only as catalog keys and slots, rendered by the `*Out` operations through `Msg.Catalog.Render`. Time slots are UTC.
- **Where tests run.**
  - Tests run on throwaway stacks only. Slot B is for load and compile only. Its production is `OCUTALONPKG.FoundationProduction`, not `OcuTalon.Production`, so production-bound tests fail there.
  - The repository is public: fixtures use the existing fixture names only.

## Technical Decisions

**30.6 The invalid-reply warning (DW-498, DW-505).**

- **Why.**
  - When `Decide` refuses a decide or diagnose reply as `invalid`, `Conclude` logs one Type 3 warning in the decision's trace session, through `Bridge.Redact.Text`: "The reply check refused the reply of the decision <Ref>: " plus `problem`. Story 5.12 added it.
  - `Judge` sets `problem` to `GetErrorText` of the check, or to "After the reply filter ran: " plus its first 400 characters.
  - For MAXLEN and datatype failures, IRIS's text quotes the value. #7201 `DTMaxLen` carries the value and the MAXLEN. #5802 `DatatypeValidationFailed` carries `Class:Property` and the value.
  - On a local install that watches OcuTalon's own production, `Watch.Reader`'s evidence read of the event log can carry that text into a later model request. U-193 kept this corner only on the condition that the warning quotes no reply content.
- **The rule.**
  - For a failure with a property and a limit, build the text from the status's error code, property and limit. Add the measured length (a computed `$Length`, never the value), for example "Evidence element 6: 42 > 32".
  - For any other failure (not one JSON object, or a code with no property and limit, such as a reply class's own `%OnValidateObject` error), name the error code and the reply class only.
  - The rule covers both paths: the first check and the check after the reply filter. "No reason is left once the reply filter has run" already quotes nothing.
- **Where.**
  - Only `Decide.Judge` and its caller in `Bridge/Process/Decide.cls` change.
  - Keep one warning per invalid reply, the `REFUSED` prefix with the Ref, the Redact wrapper, and no warning for other fallbacks (`Test.Watch.Payload.TestOtherFallbacksLogNothing`).
  - The reply class name comes from the runner's `ReplyClass` setting at run time, and the bridge code names no OcuTalon package (AD-2).
- **The catch.**
  - `CheckReply` returns a `GeneralError` whose text embeds the original error text, so `Judge` sees no code or parameters. The original status has to reach `Judge` some other way, inside `Decide.cls`.
  - `CheckReply`'s own message ("The reply check failed…") is pinned by `Test.Fix.Kind` and `Test.Watch.Payload`.
  - Nothing in the planning documents says how a list element's position shows in the status. Measure it.
- **Pins that change on purpose.**
  - `Test.Watch.Payload.TestRefusalTrace` asserts "The reply check failed", the lowercase field name "evidence", and `[redacted]` for a key in a refused value. That last check becomes "neither the key nor the marker".
  - `Test.Watch.Diagnose`, line 287, asserts "The reply check failed".
  - The new test goes in `OcuTalon.Test.Bridge`: a refused reply whose failing value carries a unique marker gives a warning without the marker, on both paths.
- **DW-505.**
  - `x [ "a"_y` evaluates as `(x [ "a")_y`. `AssertTrue`'s `''value` turns `"0"_id` into a nonzero number, so `Test.Agent.KeyScan`, line 123 (Lane A), can never fail. Parenthesise it.
  - Add the rule to `docker/tests/test-class-rules.sh`. The script needs no IRIS. Each rule first runs on synthetic classes that break it, keep it, or only mention it in a comment. A failure prints file:line, never the line itself.
  - The script is not in Lane A's listed files (Lane B's Stories 2.2 and 2.9 edited it last). Name it as the footprint extension that DW-505 names.
  - A rough scan of `src/` also flags `Test/Data/PublicSettings.cls`, line 105 (`now ] $Translate(…)_"Z"`, last edited by Story 16.8, an Epic 16 story in Lane B's files). The new rule fails there unless the spec gate rules a one-line fix in that file or scopes the rule.

**30.1 Compaction (AD-20, AD-6, AD-8).**

- **Spec status.** The planned spec (ready-for-dev, not validated) was written before Stories 5.7 and 5.12 changed `Decide.cls`, and 30.6 changes it again. Recheck its `Decide.cls` tasks at the spec gate.
- **Open at the spec gate.**
  - **V1 (veto: an AD-20 amendment).** Three more triggers for the seeded fallback:
    - a summarizer request over the limit;
    - a first request still over the limit;
    - a fork that fails its save or reopen.
  - **R1 (for the owner).** A first request between 40,000 and the limit can still pass 100,000 inside the loop. Options:
    - (a) seed instead;
    - (b) Decide refuses a tool-capable turn whose non-history part is above about 46,000;
    - (c) accept, with `reopen_if`.
  - **Spine notes.** AD-20, AD-8, AD-6 and AD-22.
- **What exists.**
  - `Decide` sets `Request.Compact` above `COMPACTTOKENS` (40,000) and falls back to `too_large` above `RequestTokenLimit`. The runner ignores the flag today.
  - A linked turn runs `AnswerLinked`: the link lock, then `OpenSession`/`NewSession`, then `Converse` (`Chat`), then `SaveLinked` (`%Save`, then `ConversationLink.Point`).
  - `Bridge.Compaction` holds `PREFIX` and `Prompt()`. The mock has `A/summary.json` and `A/summary-off-schema.json`.
  - The code-rule pins are `CHATTERS`, `SESSIONMAKERS` and `LINKNAMERS`. A compaction class outside the adapter must be added to them on purpose.
- **The design.**
  - The runner compacts in its own job, before `Chat`, outside every callback. A callback that calls AI Hub's native library deadlocks.
  - The call is `ForkAndSummarize(provider, "", k, prompt, 0)`, where `k` keeps the last user turn whole and comes from `GetContext()`. With no older history, nothing is compacted. `Summarize` in place is never used.
  - The link moves to the fork only after a check: the first non-system message is a user message, and every tool result follows its call. Then the fork is `%Save`d.
  - An exception or a failed check gives a fresh, seeded session. A compaction failure is never the turn's `FallbackReason`.
  - The summarizer gets effort `low`, a 20 s timeout and no retries. Decide adds 20 s to a flagged linked turn, at most `MAXTIMER` (110).
  - Usage is one row: agent `compaction`, `Estimated` 1, about 4 characters a token, priced at the summarizer model's rate.
  - The live smoke test runs only in release-candidate runs on the real model. Until it is wired in, `thinkingHistorySmoke` reads "not run".
- **Ledger.**
  - **DW-125 and DW-130.** The spec addresses them.
  - **DW-93.** Time `Precheck` at 100,000 `Usage` rows. At 250 ms or less (median), no code change.
  - **DW-483 (U-191).** Measure the invalid rate per reply kind after Story 5.12 first. Build the one retry only if diagnose still falls back on `invalid` in more than about 1 in 50, and only within NFR-7's 20 s diagnosis budget. The retry is a veto item. U-191's ledger line is filed under DW-493 by mistake.
  - **DW-386 (U-184) and DW-448 (U-185).** The spec declines both to the burn-down story for size. Until the lead re-owns them, the ledger still lists them as 30.1's.
    - DW-386: `Bridge.Redact` must cover every `key_like` pattern of `docker/tests/lib-keys.sh`, with one test per shape. It misses `dop_v1_` and PEM private-key headers today.
    - DW-448: `KeyProof.Walk` decodes `$List` elements. Measure the compressed `%Stream.Global*` chunk case on a throwaway, or close it wontfix with the evidence. Don't edit Lane B's `ReferenceHits` copy (DW-474).

**30.5 Mixed and unfinished (AD-16, AD-15, AD-18).**

- **Spec status.** The planned spec (ready-for-dev, not validated) predates these rulings, and the spec gate must apply them.
- **Q1.** `Watch/IncidentManager.cls` is now Lane A's and uncontended. The one-line edit in `Result` is allowed: it calls `ResultNotice` for every result, not only a final one. Story 30.5 is not split; the new 30.6 is DW-498's and unrelated.
- **U-182 (kept): AD-16 is extended.**
  - `FixResult` gains `Unreached`.
  - A resend stops at the first copy that errs (`stopped`, `refused` or `error`).
  - A run where no copy went is couldn't start: `NOTRUNNING` for a stop, otherwise `NOSTART`. A throw before any copy stays `NOREAD`.
  - `result.stoppedPartway` follows `couldNotStart` in the order.
  - The extension goes into the spine with the marker. The spine lint's baseline is 8 low.
  - The owner's condition: the text gives three counts (resent, the copy that erred, not tried) and says that nothing else was changed. A test pins a stop at copy k of n.
- **U-183 (kept).**
  - 30.5 adds `unreached` to `Live.Payload.Incident`, and `result.stoppedPartway` with its count-of-one form to the Watch catalog. The chat notice uses it.
  - The page's pick and the still-resending band go to Lane B's Story 31.2 (DW-472, DW-473). 30.5 makes no `web/` edit.
- **V1 (veto at the spec gate).** `FixRun.Unreached`, written with `ResentAt`, because the waiter and `Sweep` end runs later, in other jobs.
- **Today's code.**
  - The waiter runs under `WAITLOCK` and waits `WAITSECONDS` (60). At timeout it logs `LOGWAIT`, sends nothing and leaves the row `executing`.
  - `ResultOf` always sets `Final` 1.
  - `End` and `Mark`, under `RUNLOCK`, are the only writers of a run's end.
  - `IncidentManager.Result` treats a result that is neither final nor interrupted as progress.
  - `Test.Fix.Executor.TestSweepLeavesRunsOfTheWaiterAndOfStory305` pins `Sweep`.
- **The result key order.**
  - `Watch.Notice.ResultKey` and the page's `resultView` use the same order, and the first match wins:
    1. `executing` gives `stillResending`;
    2. `Interrupted` above 0 gives `interrupted`;
    3. nothing counted and a `Reason` set gives `couldNotStart`;
    4. (new) `Unreached` above 0 gives `stoppedPartway`;
    5. failed again and skipped together give `failedAndSkipped`;
    6. failed again alone gives `failedAgain`;
    7. skipped alone gives `skipped`;
    8. anything else gives `allThrough`.
  - A result that is neither final nor interrupted also maps to `stillResending`, and the mixed result's slots gain `resent`.
- **Ledger.**
  - **DW-384.** A past-expiry Execute is couldn't start with `NOSTART`, through `CouldNotStart`. `FinishExecution` moves the row to failed.
  - **DW-419.** Report unreached targets by how far the run got, including 30.4's start read that times out on a stopped production.
  - **DW-469.** Pin with a test that `{time}` of `watch.productionStopped` and `watch.itemDisabled` renders with the zone label (ET on the online demo), for both IRIS's stop time and the check's detection time.
  - **DW-484.** Agent-written reply times have no zone label. Route them through the catalog's zone-labelled format, or have the chat agent's prompt label the zone. 1.0.0 if cheap, otherwise defer.
  - **DW-500.** For the user's own command, Triage's reasons should say what was asked, not describe its own tool limits. The fix is the prompt (Lane A Agent). 1.0.0 if cheap, otherwise burn-down.

**Keep consistent with the done stories.**

- **30.4.**
  - `Checks` writes `BackgroundCheck.Reported` in its single `UPDATE` keyed by `Ref`. The first reading run is a baseline.
  - A finding Item is `untrusted`, goes to `Intake` only, and has a trace session of its own (AD-26).
  - After `StartExecution`, the executor reads the target's state through `Watch.Reader`. `stopped`, `suspended` and `network_stopped` give couldn't start with `NOTRUNNING`.
- **30.3.**
  - `ApprovalRequest` holds `ToolSource` and `Runner`.
  - A replay with no provider key closes the row `failed`.
  - Keep the identity fields of `Replay.ActionEntry` and `Fix.Executor.ActionEntry` in step (DW-461).
- **30.2.** `Bridge.Time.DaysCutoff` is the shared day check and UTC cutoff.

**Burn-down candidates**:

- **DW-470.** A replay that fails for lack of a provider key, or because the provider can't be reached, says so in catalog words and says nothing was changed.
- **DW-444.** A start-only `Reconcile` closes a `tool_call` left `executing` by a crash, as interrupted.
- **DW-462.** The priority flake: `TestAnswerBeforeTheTaskExists`.
- **DW-371.** The rest: `IncidentManager.Purge` adopts `DaysCutoff`.
- **DW-437.** Waits for a product call.
- **DW-386 and DW-448,** if the lead accepts 30.1's decline.

## UX & Interaction Patterns

- **Mixed:** "45 of 50 orders went through. 2 failed again (the order date still wasn't accepted), and 3 had changed since the dry run, so I skipped them. I won't retry any of them without a new approval."
- **Still running:** "Still resending: 30 of 50 orders have gone through so far. I'll tell you when it's done." With one done: "1 of {count} {item noun} has gone through so far."
- **Cut off by a restart:** "The resend stopped when OcuTalon restarted: 30 of 50 orders went through. The other 20 need a new approval." `stoppedPartway` follows this shape but must not borrow the restart cause.
- **Couldn't start:** "Nothing was resent: {reason}. Nothing was changed." The reason is `NOTRUNNING` ("the production isn't running") or `NOSTART` ("OcuTalon couldn't start the resend").
- **On the page:** each request card has its own result band, and on the web every result is followed by "Recorded in the IRIS audit log."

## Cross-Story Dependencies

- **Order.** 30.6 runs first, then 30.1, then 30.5, then the burn-down.
  - 30.6 and 30.1 both change `Bridge/Process/Decide.cls`.
  - 30.6's rule covers the trace warning only. If 30.1 builds DW-483's retry, its spec gate rules what check text the retry may carry.
- **30.6 and the demo.** 30.6 reaches the online demo with the next deploy of Epic 30's merge.
- **30.1 and Epic 9 (merged).**
  - Story 9.5's release-candidate run carries 30.1's live smoke test.
  - `Eval/**`, `Test/Eval/**`, `eval/run.sh` and `docker/tests/test-eval-set.sh` are Lane A's and uncontended.
- **30.1 and 30.2.** `Bridge.Purge` removes the AI sessions that a fork or a rotation leaves behind.
- **30.5 and Lane B.**
  - Story 31.2 takes the page's stopped-partway pick, the still-resending band, DW-443 and DW-454.
  - Until then, the page shows a partway run in the old wording.
- **30.5 and Epic 12.** Telegram's in-place result edit sees a progress notice, then the final notice, with the same ApprovalRef.
- **Lane A's files.**
  - `src/bridge/**`, `Agent/**`, `Fix/**`, `Watch/**` (with `IncidentManager.cls`), `Checks/**`, `Eval/**` and `Test/Eval/**`.
  - `Msg/Catalog/Watch.cls`, `Live.Payload.Incident`, `Live.Payload.Check` and the Lane A tables.
  - `Install.Step.Retention` and `.Watch`, `ci/mock/scenarios/A/`, and `OcuTalon.Test.<Area>` for its areas.
- **Shared files.**
  - Existing `Install/**` files are shared with Epic 15.
  - `Test/Data/Tables.cls` is shared by entry.
  - `docker/tests/test-class-rules.sh` is outside the list above: 30.6 names it as a footprint extension.
- **Never touch.** `.github/workflows/lane-a.yml` and `ci/units.sh`.
- **Lane B (read only).**
  - `Intake`, `OutcomeRouter`, `Notify`, `Core.BridgeSink`, `Conversation`, `Data.Pairing`, `Data.Time` and `Data.Ownership`.
  - `web/**` and the `Usage` index pin.
