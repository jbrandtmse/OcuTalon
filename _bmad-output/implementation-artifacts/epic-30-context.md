# Epic 30 Context: Lane A post-demo hardening

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Epic 30 finishes the Lane A parts of the demo-path stories that the owner moved past the demo path. Each part lands before 1.0.0, the first release (no 0.1.x is cut). Long conversations are compacted before their requests near the size limit. Old records are purged on schedule. An approved tool call replays exactly once with no model. A stopped production or a disabled item reaches the user once. A resend that is mixed, still running or stopped partway says exactly how far it got and never claims a change that did not happen. Stories 30.2, 30.3, 30.4 and 30.6 are done. This run is part 1 of a two-part merge (U-207): 30.5 is next and merges with 30.6. Story 30.1 stays backlog for the later part, and the burn-down story (30.7) comes last.

## Stories

- Story 30.1: Long conversations are compacted under the limit (backlog; later part)
- Story 30.2: Old messages and records are purged on schedule (done)
- Story 30.3: An approved tool call runs exactly once, with no model (done)
- Story 30.4: A stopped production or a disabled item is reported once (done)
- Story 30.5: Mixed and unfinished resends say how far they got (next; spec re-opened as draft)
- Story 30.6: The invalid-reply warning names what failed, never the reply (done)
- Then the burn-down story (30.7), if the burn-down gate charters one

## Requirements & Constraints

- **Honest results.**
  - Each fix run gets exactly one final `FixResult`, and at most one in-progress result.
  - Nothing is resent behind the user's back. A copy that fails again is never retried without a new approval. Originals are never changed.
  - "Had changed since the dry run" is only for a target that really changed. A result never reads all-through while a target was left out.
- **No model-written state on a user's turn (DW-500, widened, built first).**
  - On any user chat turn (the always-answered Tell-now override), Triage's reasons never describe production state, what Triage can or can't access, or whether anything needs the user.
  - They only classify the turn as the user's own message, for example "A question from the user; the user is answered directly".
  - A reason like "nothing needs the user at this moment" is a model-written all-clear. Only code may give an all-clear.
- **Public text.**
  - Every new reason sentence, key, slot or prompt wording is a veto item.
  - Producers never render. Users see text only as catalog keys and slots, rendered by the `*Out` operations through `Msg.Catalog.Render`.
  - Time slots are stored in UTC and show " ET" on the online demo.
- **Stored data.**
  - Persistent and message classes are append-only. Keep the committed `Storage` block and write the compiler's new slots back verbatim.
  - Each new column is its own veto item and gets our own entry in `Test.Data.Tables`.
  - Epic 9's eval tests pin stored fields (30.4's `BackgroundCheck.Reported` turned CI red until it joined `Watch.Ops` `FIELDS`), so check every new column against `Test.Eval.*`.
- **Audit.** Action entries go only through the audit writer. A progress result writes none.
- **Where tests run.**
  - This run is runner B: slot `ocutalon-slot-b`, web port 52802, lock dir `locks/lane-b`. The 30.5 spec's Verification block still names lane-a, 52801 and `ocutalon-slot-a`. Correct it at the spec gate.
  - Slot B is for load and compile only. Its production is `OCUTALONPKG.FoundationProduction`, not `OcuTalon.Production`, so production-bound tests fail there. Every other test runs on throwaway stacks.
  - The repository is public, so fixtures use the existing fixture names only.

## Technical Decisions

**30.5: the spec-gate rulings (G0-G5) win over the spec's older rows.**

- **G0. Order.** DW-500 is planned and built first. It is the demo launch's visible fix.
- **G-DW500. Two ways to build it; record which one under Design Notes.**
  - Preferred: change Triage's instructions in `Agent/Triage.cls`. Add eval cases on the mock for the four "Try it yourself" chips' exact texts: "Which productions are running?", "Is anything wrong right now?", "What was that failure earlier?" and "What can you do?". Their chat scenarios are `ci/mock/scenarios/B/try-it-*.json`, so read them and don't change them.
  - On the host, real Haiku's reasons drew tool-limit wording under chips 1, 3 and 4 and a model-written all-clear under chip 2. The mock can't reproduce that wording. The Contest Planner checks real Haiku on the host after the merge.
  - Fallback, only if the decision payload already marks the override: the decision strip shows only the override line, and the reasons move into Decision details (`web/src/app/chat/decision-strip.ts` and `decision-view.ts`, free since Epic 4 merged). Pin it with a web unit test. Never change `api/api-types.ts` or `live/live-store.ts`.
  - Never edit `Agent/Chat.cls` (Epic 11's). Chip 1's missing running state (DW-541) belongs to 30.1.
- **G-DW519. Share two rules that are copied today.**
  - `Tools.RecentActivity` (Story 5.13, merged) has its own copies of `WatchAnswers.WatchNames` (Private) and of the catalog's " ET" time rule (`Shown`, which copies `Msg.Catalog.SlotText`). Make both shared and call them from `RecentActivity`. Keep every `Test.Tools.RecentActivity` test green.
  - **Open:** the spine makes the renderer `Msg.Catalog` Lane B's after Epic 0, and the ledger's suggested home, `Data.Time`, is Lane B's too. The spec gate must name a Lane A home or rule the cross-lane edit. No other worktree has changed these files.
- **G-DW484 (narrow).** Only the chat's reminder reply gains the zone label. If that needs `Agent/Chat.cls`, `Tools/ReminderTools.cls`, `Test/Tools/Reminders.cls` or `Test/Schedule/ReminderChat.cls` (all Epic 11's), HALT with an intent gap that names the file.
- **G-DW469.** A test pins that `{time}` in `watch.productionStopped` and `watch.itemDisabled` renders with the zone label, for both IRIS's stop time and the check's detection time.
- **G1. U-182: the AD-16 extension (now written in the spine).**
  - A resend stops at the first copy that errs (`stopped`, `refused` or `error`) and tries no later target. The real skips go on.
  - If no copy went, the run is couldn't start: `NOTRUNNING` for a stop, otherwise `NOSTART`, with the row `failed`. A throw before any copy stays `NOREAD`.
  - Otherwise the final `FixResult` carries `Unreached`: the copy that erred plus every target after it. The result reads `result.stoppedPartway`.
  - The owner's condition: the text gives three counts (resent, the copy that erred, not tried) and says nothing else was changed, and a test pins a stop at copy k of n. The spec's rows 14, 15 and 18 and its V3 text ("The other {remaining} need a new approval") don't meet this yet and must be re-worded.
  - **Conflict to settle at the gate.** The spine says `Skipped` holds only the targets that really changed. The spec counts Skipped as Total − Resent (`Look`, rows 14-15, `3|2|2|0|1`), and its V1 rejected the exclusive form.
    - With exclusive Skipped, the page's unchanged `resultView` would show a partway run with no failure as all-through until Story 31.2.
    - With inclusive Skipped, the page shows `result.skipped`'s false "had changed" claim instead.
  - Neither page reading is honest until Story 31.2. Settle the counts, the Action entry and `EndMarked`/`EndLeft` accordingly.
- **G1b. U-183: the payload, catalog and chat parts.**
  - 30.5 adds `unreached` to `Live.Payload.Incident` (append-only), plus `result.stoppedPartway` and its count-of-one form in `Msg/Catalog/Watch.cls`. The chat notice uses the new key.
  - The page's result pick and its still-resending band go to Story 31.2 (DW-472, DW-473). Apart from DW-500's fallback, 30.5 makes no `web/` edit.
- **G3. Q1.** `Watch/IncidentManager.cls` is Lane A's and uncontended now that Epic 9 has merged.
  - The one-line edit in `Result()` is allowed: it calls `ResultNotice` for every result, not only a final one.
  - The story isn't split. The spec's "contended" and "split" notes are stale.
- **G4. The README sentence.** Append "It also tells you once when a production stops or one of its items is disabled." to the second item under "What you can use it for".
  - `docker/tests/test-readme.sh` pins that item word for word (`ITEM2`, the `use-cases` check), so update the pin.
- **G5.** DW-384 and DW-419 are built as the spec's rows plan them.
  - DW-384: an approved Execute past its expiry ends as couldn't start with `NOSTART`, through `CouldNotStart`.
  - DW-419 includes 30.4's start read that times out on a stopped production.
- **Kept from the spec (the veto window).**
  - `FixRun.Unreached` is written in the same save as `ResentAt`, because the waiter and `Sweep` end runs later, in other jobs. `FixResult.Unreached` is a new slot.
  - The waiter sends one progress result (`Final` 0) at the drop, and only when:
    - the run is unmarked;
    - its row is still executing;
    - at least one read in the wait succeeded.
  - The progress result stores nothing, writes no audit entry, and `LOGWAIT` stays.
  - `Sweep`'s `EndLeft` loses the `lastAt` gate.
  - `End` and `Mark`, under `RUNLOCK`, stay the only writers of a run's end. `Resend` stays the only namespace switch.
  - The mixed result's slots gain `resent`.
- **Result key order.** `Watch.Notice.ResultKey` (first match wins):
  1. `executing`, or a result that is neither final nor interrupted, gives `stillResending`;
  2. `Interrupted` > 0 gives `interrupted`;
  3. nothing counted and a `Reason` set gives `couldNotStart`;
  4. (new) `Unreached` > 0 gives `stoppedPartway`;
  5. failed again and skipped together give `failedAndSkipped`;
  6. failed again alone gives `failedAgain`;
  7. skipped alone gives `skipped`;
  8. anything else gives `allThrough`.

  The spine's "Result texts" convention doesn't list step 1's progress rule or step 4 yet. Raise it as a spine note.

**Keep consistent with the done stories.**

- **30.6.** A refused reply's trace warning quotes no reply content. Any new warning (for example `LOGPARTWAY`) goes through `Bridge.Redact` and names IDs and counts, never message content.
- **30.4.** After `StartExecution`, the executor reads the target's state through `Watch.Reader`. `stopped`, `suspended` and `network_stopped` give couldn't start with `NOTRUNNING`. A finding Item is `untrusted` and goes to `Intake` only.
- **30.3.** An approved call runs once with no inference request. Keep the identity fields of `Replay.ActionEntry` and `Fix.Executor.ActionEntry` in step (DW-461).
- **30.2.** `Bridge.Time.DaysCutoff` is the shared day check and UTC cutoff. `Bridge.Purge` relies on the runner being the only code that saves AI sessions.

**30.1 (later part; recheck at its spec gate).**

- Its planned spec predates Stories 5.7, 5.12 and 30.6's changes to `Bridge/Process/Decide.cls`.
- Still open: V1 (three more seeded-fallback triggers, an AD-20 amendment) and R1 (first requests between 40,000 tokens and the limit).
- DW-541 is new and routed to 30.1: chip 1 needs a code-built running state in `list_productions`, or the chip's text becomes "Which productions can you watch?".
  - Only at no date cost: if it would make the re-open merge after Epic 13, re-own it to the first daily release after 1.0.0.

**Burn-down candidates:**

- **DW-544.** A nested field's MAXLEN failure gets a bare "ERROR #9406" warning. Decision-pending.
- **DW-470.** A replay with no provider key says so in catalog words.
- **DW-444.** A start-only `Reconcile` closes a crashed `tool_call`.
- **DW-462.** The priority flake.
- **DW-371.** The remaining `Purge` adopts `DaysCutoff`.
- **DW-386 and DW-448,** if the lead accepts 30.1's decline.

## UX & Interaction Patterns

- **Mixed:** "45 of 50 orders went through. 2 failed again (the order date still wasn't accepted), and 3 had changed since the dry run, so I skipped them. I won't retry any of them without a new approval."
- **Still running:** "Still resending: 30 of 50 orders have gone through so far. I'll tell you when it's done." When completed is 1: "1 of {count} {item noun} has gone through so far."
- **Cut off by a restart:** "The resend stopped when OcuTalon restarted: 30 of 50 orders went through. The other 20 need a new approval." `stoppedPartway` is new public text: it must not borrow the restart cause, and it must meet U-182's three-count condition. The UX's Results table has no "Stopped partway" row yet.
- **Couldn't start:** "Nothing was resent: {reason}. Nothing was changed." The reason is `NOTRUNNING` ("the production isn't running") or `NOSTART` ("OcuTalon couldn't start the resend").
- **Decision strip on a user's own turn:** the reasons classify the message and never report state or tool limits (DW-500).

## Cross-Story Dependencies

- **Order.** 30.5 is next and merges with 30.6 (part 1). 30.1 comes later, then the burn-down.
- **Merged since the last compile.**
  - Story 5.13 brought `Tools.RecentActivity`: read-only, trusted output, and pinned to code-built fields by `Test.Tools.RecentActivity`.
  - Epic 4 brought the four chips (Story 4.10) and freed the decision-strip web files.
- **Epic 11 (in flight).** `Agent/Chat.cls`, `Tools/ReminderTools.cls`, the reminder tests, `api-types.ts` and `live-store.ts` are Epic 11's. Don't edit them.
- **Lane B.**
  - Story 31.2 takes the page's stopped-partway pick, the still-resending band, DW-443 and DW-454. Until then the page shows a partway run in the old wording.
  - Lane B owns `Msg.Catalog` (the renderer), `Data.Time`, `Core.*`, `Data/Session.cls` and every other `Live.Payload.*`. Read them only.
  - The README and `docker/tests/test-readme.sh` are shared. G4 edits them by ruling.
- **Epic 12.** Telegram's in-place result edit sees a progress notice, then the final notice, with the same ApprovalRef.
- **Lane A's files.**
  - `src/bridge/**`, `Agent/**` (not `Chat.cls`), `Tools/**` (not Epic 11's reminder files), `Fix/**`, `Watch/**` (with `IncidentManager.cls`), `Checks/**`, `Eval/**` and `Test/Eval/**`.
  - `Msg/Catalog/Watch.cls`, `Live.Payload.Incident` and `Live.Payload.Check`, and the Lane A tables.
- **Shared by entry.** `Test/Data/Tables.cls` and `Test/Msg/Catalog.cls`.
- **Never touch.** `.github/workflows/lane-a.yml` and `ci/units.sh`.
