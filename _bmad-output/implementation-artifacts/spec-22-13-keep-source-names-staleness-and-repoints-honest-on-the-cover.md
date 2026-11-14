---
title: 'Story 22.13: Keep source names, staleness and repoints honest on the coverage list'
type: 'feature'
created: '2026-11-14'
status: 'done'
baseline_revision: 'f17c050c782868ce57a76b30b8fff3f276f03146'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-22-context.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-22-5-poll-a-read-only-mcp-tool-as-a-source.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-22-11-run-source-polls-through-the-governed-proxy.md'
warnings: []
deferred:
  - summary: >-
      A source's coverage with an empty window end (Current uses now) has no test.
    evidence: |-
      Current takes NowUtc() when toUtc is empty; every new coverage test passes an explicit window. Replacing NowUtc() with "" would read every old run as current (Apart returns 0) and no test would fail. A test in the style of TestMailboxNoWindow, with a source and an earlier run, would settle it.
    location: >-
      src/ocutalon/cls/OcuTalon/Checks/Coverage.cls (Current)
    severity: low
---

<intent-contract>

## Intent

**Problem:** Story 22.5 (Part A, merged) gives an admin a `source` row and its coverage entry. Four things read wrong on the digest's coverage list, and none of them needs the bridge:
- A source can be named "Mailbox", so the list can show two "Mailbox" entries (DW-1325).
- A source polled less often than the digest span reads stale between its runs (DW-1327).
- A source repointed to another server, tool or arguments keeps the old target's history (DW-1328).
- The digest's sentences name the connected mailbox "the Mailbox" ("I checked … and the Mailbox.") and "Mailbox" ("Not everything: Mailbox.").

**Approach:** This is the split of Story 22.11 the Planner approved at ~13:20Z Nov 14 (item 1). It is carved from 22.11's planned spec (`spec-22-11-run-source-polls-through-the-governed-proxy.md`, its matrix rows 8-11, its DW-1325, DW-1327 and DW-1328 tasks and the Digest task), with the ~13:20Z rulings applied. 22.11 keeps the poll run.
- `McpOps` refuses the name "Mailbox" with its own outcome `reserved_name` (DW-1325).
- Coverage lets a source's latest run since its `CreatedAt` count when it is within max(the window, its interval plus 180 s) of the window's end (DW-1327).
- `Watch.Ops.SetSource` moves a repointed source's `CreatedAt` to now (DW-1328, RESET).
- `Digest.Process` names the connected mailbox "the mailbox" in both sentences (~12:45Z and ~13:20Z item 4).

## Boundaries & Constraints

**Always:**
- **Lanes (AD-29).** Lane A files only: `Mcp/Ops.cls`, `Watch/Ops.cls`, `Checks/Coverage.cls`, `Digest/Process.cls`, `Data/BackgroundCheck.cls` (doc only), and the tests `Test/Mcp/SourceSet.cls`, `Test/Digest/Coverage.cls`, `Test/Digest/Compose.cls` (Lane A rows only).
- **The latest run counts (AD-18, DW-1326).** There is no "all runs passed" rule.
- **AD-28.** The all-clear comes only from `Checks.Render`; the mailbox is not a watch (a lone Mailbox row is nothing watched). Both stay as they are.
- **AD-33.** `Checks` alone writes the run fields. 22.13 writes none of them: the repoint moves only `CreatedAt`, which `Watch.Ops.SetSource` already owns.
- **Approved public text stays verbatim:** "That name belongs to the connected mailbox. Choose another name." (Planner ~09:40Z) and "the mailbox" in the two sentences (Planner ~12:45Z and ~13:20Z item 4). No other user-facing string is added or changed.
- **Labels stay.** Where "Mailbox" is a label (the coverage lines and the digest lead `digest.passed`/`digest.notChecked*` {entry}, the check rows on the page and in Telegram, Settings), it is unchanged. `Checks.Coverage.ENTRYMAILBOX` stays "Mailbox".

**Never:**
- Edit the bridge (`src/bridge/**`), `Checks/Process.cls`, `Mcp/Proxy.cls`, `Mcp/Attach.cls`, `Core.*`, `Web.*`, `web/**`, `Msg.*`, `Data.Precedent`, `Channel.*`, `Test/Contract/**`, `Test/Core/**`, `Test/Live/**` or any Lane B test. If a Lane B test pins the old behaviour, stop with `## Clarification Needed`.
- Take 22.11's scope (the run, the baseline, Items, the stop notice, `Reported`) or 21.5's scope (the Settings source form; the HTTP mapping of `reserved_name` to 400 is lane C's cross-lane bullet, ruled ~13:20Z item 3). 22.13 only returns the outcome.
- Delete any row, `CheckRun` or otherwise. Delete, skip, tag off or shorten a test.

## I/O & Edge-Case Matrix

Fixtures: server `zz`, tool `zz_lookup`, source "Jira", interval 15 unless stated.

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| 1 Reserved name (DW-1325) | `SetSourcePoll` with Name "Mailbox", " mailbox " or "MAILBOX". | Ok 0, outcome `reserved_name`, message `MESSAGESOURCERESERVED` ("That name belongs to the connected mailbox. Choose another name."). No row, no audit entry, no `CheckChanged`. | "My Mailbox" and "Mailboxes" are accepted. Every check before the name step (sender, online demo, server, tool) answers as today. |
| 2 Long interval, current (DW-1327) | A 24 h digest window; a 2,880-minute (48 h) source created before the window, with no run in the window; its latest run passed 30 h before the window's end. | The row takes that run through the latest-run rules: `passed`, checked at that run. | A latest run that was `not_checked` or `failed` gives that result and reason, as for a run in the span. |
| 3 Long interval, stale (DW-1327) | As row 2, the run 50 h before the window's end. | `digest.notCheckedStale` {that time}, as today. | none |
| 4 Before CreatedAt (DW-1327, DW-1328) | As row 2, but the row's `CreatedAt` is after that run. | The run never counts: no run since `CreatedAt` → `missed` from the span's start, as for a new row today. | none |
| 5 Other kinds | A production or queue row with no run in the span and an earlier run. | Unchanged: stale. | none |
| 6 Repoint (DW-1328, RESET) | An update of "Jira" with a different server, tool or arguments (`%EXACT` compare). | Same Ref. `CreatedAt` and `NextDueAt` become now. Coverage counts only runs since. `Reported`, the run fields and `CheckRun` rows are not touched (22.11's run takes the next good run since `CreatedAt` as a baseline). | none |
| 7 Same target | An update that changes only the interval, or only the name's letter case. | `CreatedAt` kept (and `Reported`, the run fields). `NextDueAt` now, as today. | none |
| 8 "I checked" sentence | The session watches the Orders production, a source "Jira" and the mailbox. | "I checked the Orders production, Jira and the mailbox." (and the `digest.checkedQuiet` variant). The coverage line keeps "Mailbox". | none |
| 9 "Not everything" sentence | The mailbox row is not checked (or failed), and the lead does not apply (a failed row exists, or no row passed). | The `checks.notEverything*` part's `whatFailed` names it "the mailbox": "Not everything: the mailbox." Other entries in `whatFailed` are unchanged ("Orders production", "Jira"). The coverage lines keep "Mailbox". | none |

</intent-contract>

## Code Map

Paths are under `src/ocutalon/cls/OcuTalon/`. Line numbers are at `6a5a730a` (feature `f138fcf8` merged).

- **McpOps** (`Mcp/Ops.cls`): doc L3-12 and L34-37 (the outcome words); `MESSAGE*` L56-86; `OnSetSource` L192-225: the name trimmed L206, `bad_name` L207, arguments L208-209, interval L210-211; `Answer` L890.
- **Watch.Ops** (`Watch/Ops.cls`): `SetSource` L228-269 (doc L228-231; the existing-row path L242-244 keeps `CreatedAt`; L252-258 set the fields and `NextDueAt`); `RefOf` L357-371 (the natural key is case-insensitive on the name).
- **Coverage** (`Checks/Coverage.cls`): `MISSEDSECONDS` L49; `ENTRYMAILBOX` L66; `WatchRow` L290-352: spanStart L295-297 (already from `CreatedAt`), **no run in the span L307-314** (`EarlierRun` L308; stale L309-310; missed L311-312); the source's allowed gap L316-319 (`IntervalMinutes`×60 + `MISSEDSECONDS`); latest-run rules L330-351. `Runs` L455-464; `EarlierRun` L467-472 (selects `RanAt` only, any time before spanStart); `Apart`; `RecordRun` L553-563 (doc L550-551).
- **Digest** (`Digest/Process.cls`): `Finish` L491-530 (L514-518 build `named` for "I checked", `"the "_entry` unless the row is a source; L527 `whatFailed` from `verdict.named`); `Verdict` L576-613 (`named` from Render's ordered rows, which carry no `kind`; `sources` L604; the mailbox-only test L607); doc items around L34.
- **Rows:** `Data/BackgroundCheck.cls` `CreatedAt` doc; `IntervalMinutes` L62.
- **Catalog** (read only, `Msg/Catalog/Watch.cls`): `digest.checkedQuiet` L468, `digest.checked` L475, `digest.notCheckedStale` L546; `checks.notEverything*` ("Not everything: {whatFailed}.").
- **Tests:**
  - `Test/Mcp/SourceSet.cls`: `TestSetRefused` L150 (`bad_name` block L166-172), `TestUpdate` L103; helpers `Run` L531, `Refuse` L541, `SetCommand` L548, `MakeRows` L601, `Clean` L671, `Leftovers` L693.
  - `Test/Digest/Coverage.cls`: `TestStale` L308, `TestSourceIntervalGap` L360; helpers `Source` L821, `Run` L845, `Slots` L860, `Built` L875.
  - `Test/Digest/Compose.cls` L493-509 `TestCheckedListSourceBare` (expects "the Mailbox" today).
- **CI:** `Test.Mcp.*` in `shard:lane-a@rest` (`shards-2`); `Test.Digest.*` in `@Install,Digest,Eval` (`shards`). No new class, unit, group or area.

## Tasks & Acceptance

**Execution:**
- [ ] `Mcp/Ops.cls` -- **DW-1325.** In `OnSetSource`, right after the `bad_name` check (L207): when the trimmed name equals `##class(OcuTalon.Checks.Coverage).#ENTRYMAILBOX` in any letter case (`$ZConvert(…, "L")` on both sides), answer outcome `reserved_name` with the new `Parameter MESSAGESOURCERESERVED = "That name belongs to the connected mailbox. Choose another name.";`. Nothing is written. Add `reserved_name` to the class doc's outcome list and a doc bullet (DW-1325; who reads it: 21.5's Settings relay, ruled as lane C's cross-lane bullet).
- [ ] `Watch/Ops.cls` -- **DW-1328, RESET.** Add `Parameter REPOINTRESETS = 1;` with a doc line (ruled ~13:20Z item 2; 0 would be the "keep" reading). In `SetSource`, on an existing row, when `REPOINTRESETS` is 1 and the stored `Server`, `Tool` or `Arguments` differ (exact compare) from the new values, set `row.CreatedAt = now` before the save. Restate the method doc: a repeat of the key keeps `CreatedAt` unless the target (server, tool or arguments) changes, when `CreatedAt` becomes now, "a source's CreatedAt is when its target was set"; run fields, `Reported` and `CheckRun` rows are never touched here.
- [ ] `Checks/Coverage.cls` -- **DW-1327.** At L307-314, for a `source` row (`Kind = Checks.Process.#SOURCEKIND`) with `IntervalMinutes` > 0:
  - extend `EarlierRun` in place (Rule 2) to also return the run's result, reason and finding, and to accept an optional lower bound so a source's earlier run counts only at or after the row's `CreatedAt` (other kinds call it as today);
  - when that run exists and `Apart(run.ranAt, toUtc)` ≤ max(`Apart(fromUtc, toUtc)`, `IntervalMinutes`×60 + `MISSEDSECONDS`), the row takes that run through the same latest-run rules as a run in the span (L330-351: its `failed` with the finding, its reason when `not_checked`, else `passed` at its time). Otherwise: stale as today when an earlier run exists, missed when none.
  - Every other kind is unchanged. Fix the class doc and the `RecordRun` doc (L550-551) where they describe staleness.
- [ ] `Digest/Process.cls` -- **the mailbox sentences.** Add `Parameter MAILBOXINSENTENCE = "the mailbox";`.
  - "I checked" (L517): an entry equal to `Checks.Coverage.#ENTRYMAILBOX` whose row is not a source renders as `MAILBOXINSENTENCE` (not `"the "_entry`).
  - `whatFailed` (L527): build the joined list from `verdict.named` with an entry equal to `ENTRYMAILBOX` rendered as `MAILBOXINSENTENCE`; every other entry unchanged. Render's rows carry no `kind`; the entry alone identifies the mailbox here because DW-1325 refuses a source named "Mailbox" (22.5 is unreleased, so no install has one).
  - Nothing else changes: the coverage lines and the lead keep "Mailbox". Restate the doc item for the checks part.
- [ ] `Data/BackgroundCheck.cls` (doc only): `CreatedAt` gains "for a source, when its target (server, tool, arguments) was last set (Story 22.13, DW-1328)".
- [ ] Tests (hermetic fixtures removed after each test; one class per call):
  - **`Test/Mcp/SourceSet.cls`:**
    - `TestSetRefusedReservedName`: "Mailbox", " mailbox " and "MAILBOX" each answer `reserved_name` with the exact message and write no row, audit entry or `CheckChanged`; "My Mailbox" is accepted.
    - `TestRepointMovesCreatedAt`: a source created with an old `CreatedAt` (fixture); an update that changes the server, then one that changes the tool, then one that changes the arguments, each moves `CreatedAt` to now.
    - `TestSameTargetKeepsCreatedAt`: an interval-only update and a letter-case-only name update each keep `CreatedAt` (and the same Ref).
  - **`Test/Digest/Coverage.cls`:**
    - `TestSourceLongIntervalCurrent`: matrix row 2 (`passed` at that run).
    - `TestSourceLongIntervalStale`: matrix row 3.
    - `TestSourceEarlierRunBeforeCreatedAt`: matrix row 4.
    - `TestSourceRepointCountsOnlySince`: runs before a repoint (`CreatedAt` moved through `Watch.Ops.SetSource`) are not in the row; the row reads from runs since.
    - `TestStale` (production) stays green unchanged: other kinds keep stale.
  - **`Test/Digest/Compose.cls`:**
    - `TestCheckedListSourceBare` expects "I checked the Orders production, Jira and the mailbox.".
    - `TestCheckedListMailboxLower`: both the `digest.checked` and `digest.checkedQuiet` variants say "the mailbox", and the coverage line keeps "Mailbox".
    - `TestNotEverythingMailboxLower`: a digest whose mailbox row is not checked and the lead does not apply reads "Not everything: the mailbox." (with another entry beside it unchanged), and the coverage line keeps "Mailbox".

**Acceptance Criteria:**

- **DW-1325.** Given a `SetSourcePoll` named "Mailbox", " mailbox " or "MAILBOX", when McpOps handles it, then it answers `reserved_name` with "That name belongs to the connected mailbox. Choose another name." and writes no row, audit entry or `CheckChanged`. Mutation: compare without the case fold → `TestSetRefusedReservedName` red. Mutation: compare the untrimmed `request.Name` → red.
- **DW-1327.** Given a 24 h digest window and a 48 h source with no run in the window, when coverage is built, then a passed run 30 h before the window's end counts (`passed`), and one 50 h before is stale. Mutation: drop the earlier-run rule → `TestSourceLongIntervalCurrent` red. Mutation: ignore the age limit → `TestSourceLongIntervalStale` red. Mutation: drop the `CreatedAt` bound → `TestSourceEarlierRunBeforeCreatedAt` red.
- **DW-1328, reset branch.** Given a source updated with a different server, tool or arguments, when `Watch.Ops` saves it, then its `CreatedAt` is now and coverage counts only runs since. Mutation: `REPOINTRESETS` 0 → `TestRepointMovesCreatedAt` and `TestSourceRepointCountsOnlySince` red.
- **DW-1328, keep branch.** Given an interval-only or letter-case-only update, when it is saved, then `CreatedAt` is kept. Mutation: reset `CreatedAt` on every update → `TestSameTargetKeepsCreatedAt` red.
- **Integration AC (Rule 1).** Given a source repointed through `Watch.Ops.SetSource`, when the consumer `Checks.Coverage.Build` builds the session's rows, then it reads the moved `CreatedAt` and counts only runs since (`TestSourceRepointCountsOnlySince`).
- **"I checked" sentence.** Given a digest covering the Orders production, "Jira" and the mailbox, when it is composed, then it reads "I checked the Orders production, Jira and the mailbox.", and the coverage line still names "Mailbox". Mutation: restore `"the "_entry` for the mailbox → `TestCheckedListSourceBare` and `TestCheckedListMailboxLower` red.
- **"Not everything" sentence.** Given a digest whose mailbox row did not pass and whose lead does not apply, when it is composed, then it reads "Not everything: the mailbox." with the other entries unchanged. Mutation: pass `verdict.named` through unchanged → `TestNotEverythingMailboxLower` red.

## Spec Change Log

- 2026-11-14 (lead; quick gate, ordered by the orchestrator). **Split from Story 22.11** by the Contest Planner's ruling ~13:20Z Nov 14 (22.11 gate), quoted from `<coordination>/prompts/epic-22-rulings-20261113-1715.md`:
  - "1. **SPLIT: approved.** A new Story **22.13** in Epic 22 takes: DW-1325 (the reserved name); DW-1327 (staleness against max(window, interval + 180 s)); DW-1328's switch; the mailbox sentences. 22.13 lands before 16:00Z if CI allows. 22.11 keeps the poll run: the bridge, Checks and the stop notice."
  - "2. **DW-1328: RESET is confirmed.** History starts over, the next good run sets a baseline with no Item, coverage counts only runs since the repoint, and an interval or letter-case-only change keeps everything. Test both branches, with a mutation each." (The baseline is 22.11's run; 22.13 moves `CreatedAt`, which is what 22.11's baseline rule reads.)
  - "3. **reserved_name in 21.5:** approved as a cross-lane AC bullet (the orchestrator relays it to lane C). It answers 400, never 500, and the person sees the DW-1325 text. Not 22.13's code."
  - "4. **Mailbox: lowercase BOTH sentences.** (1) "I checked the Orders production, Jira and the mailbox." (2) "Not everything: the mailbox." (3) and (4) stay as labels. Pin both sentences, each with a mutation."
- Earlier rulings carried from 22.11's plan: Planner ~09:40Z (DW-1325 text verbatim, three inputs and a mutation; DW-1327 30 h / 50 h tests; DW-1326 latest run counts) and ~12:45Z (lowercase only inside a sentence; labels unchanged; the reserved-name check stays case-insensitive). The 180 s slack is kept because AD-18's Part A record already gives a source "the interval plus 180 s"; the Planner's ~13:20Z item 1 states "max(window, interval + 180 s)".
- No new public text: the two strings are approved. Veto: the outcome word `reserved_name` (a contract word; approved for 21.5's mapping at ~13:20Z item 3). No route, privilege, role, grant, resource, table, column, retention, outward action or web dependency.

## Review Triage Log

### 2026-11-14 -- Review pass
- verdicts: 25 findings -- high 0, medium 0, low 9, false 16, maybe-false 0
- findings:
  - `[false]` `reject` Blind: a repointed source reads missed straight away -- the spec's matrix row 4 and 6 say so ("missed from the span's start, as for a new row today"); a new row behaves the same.
  - `[false]` `reject` Blind and Edge: a source already named "Mailbox" is not migrated -- Design Notes decided 3 (22.5 is unreleased, no install has one); deleting rows is excluded.
  - `[false]` `reject` Blind: the reserved-name message lacks "Nothing was changed." -- the text is Planner-approved verbatim; no other text may ship.
  - `[low]` `patch` Blind: the loop that skips the gaps for a carried run is unexplained -- one contract comment added above the loop in `Checks/Coverage.cls`.
  - `[low]` `reject` Blind: Coverage header comment hard to read -- cosmetic, the exception is stated once in rule (2).
  - `[low]` `defer` Blind and Verification-gap: the empty-window-end branch of Current has no test -- recorded in `deferred:`.
  - `[low]` `reject` Blind: the max(window, interval) branch, the "since" of a carried unreachable run and REPOINTRESETS 0 are untested -- the spec's Pinning mutations name REPOINTRESETS 0 and it is observed red; the window term cannot change a result (see below); the streak start is the carried run by the spec's "same latest-run rules" over one run.
  - `[false]` `reject` Blind: a Compose test for the lead keeping "Mailbox" when not_checked -- TestCheckedListMailboxLower and TestNotEverythingMailboxLower assert the coverage line label; the lead is unchanged code.
  - `[low]` `reject` Blind: coverage tests read rows by position -- the rows are fixed (four vitals, then sources in creation order) as in the sibling tests.
  - `[low]` `reject` Edge: the carried run's streak start under-reports an outage -- the spec's rule takes the one run; fixing it loads more runs and adds branches for a rare long-interval case.
  - `[low]` `reject` Edge and Verification-gap: the window term of max(window, interval + 180 s) never decides, because the earlier run is always before the window's start -- true, but it is the Planner's wording and it changes no result; no harm named.
  - `[false]` `reject` Edge: unreadable times pass as current -- RanAt is written by the system, never malformed.
  - `[false]` `reject` Edge: an in-flight poll of the old target lands after the repoint -- 22.11's run and baseline rule; out of this story by the intent.
  - `[low]` `reject` Edge: a run in the same second as the new CreatedAt counts -- an unlikely race; the fix changes the shared Runs query.
  - `[false]` `reject` Edge: a window that ended before the repoint reads missed with an empty span -- the span clipping is pre-existing for a new row.
  - `[false]` `reject` Edge: reserved_name has no consumer yet -- 21.5's mapping is lane C's bullet, ruled at ~13:20Z item 3.
  - `[false]` `reject` Edge: a source row with no interval skips the CreatedAt bound -- McpOps allows 5 to 1,440 minutes only, so no such source exists.
  - `[false]` `reject` Edge: the RecordRun and Runs docs and the spine are not updated -- RecordRun's doc does not describe staleness; the spine is the lead's update.
  - `[low]` `patch` Verification-gap: Reported, NextDueAt and the CheckRun rows are not pinned on a repoint -- tests extended: Reported kept and NextDueAt now in `TestRepointMovesCreatedAt`, Reported kept in `TestSameTargetKeepsCreatedAt`, the CheckRun row kept in `TestSourceRepointCountsOnlySince`.
  - `[false]` `reject` Verification-gap (other): new tests are self-contained and the nine mutations map to assertions -- no defect claimed.
  - `[false]` `reject` Intent audit: reading C1 and D1 implemented; NextDueAt not asserted (covered by the patch above); Compose tests use Feed, the real mailbox row is covered by the existing TestMailboxRealSeams -- descriptive, no defect.
  - `[false]` `reject` Intent audit: reservation only at the McpOps handler -- the intent names McpOps (reading A1).
  - `[false]` `reject` Intent audit: carry-in only when the span has no run -- matrix row 2 says "no run in the window".
  - `[false]` `reject` Intent audit: no Settings surface exercised -- Web and Core are excluded by the intent.
  - `[false]` `reject` Verification-gap first attempt: diff path typo, no review -- re-run with the right path.

## Design Notes

**Governing ADs (Rule 6):** AD-18 (coverage; amended for DW-1327), AD-28 (the all-clear only from `Render`; the mailbox is not a watch), AD-29 (lanes), AD-32 (catalog keys; the sentences fill existing slots), AD-33 (`Checks` writes the run fields; untouched). No AC contradicts an AD's Rule except DW-1327, which amends AD-18's staleness rule for sources by the Planner's ruling. No NFR trips Rule 5.

**Decided (kept from 22.11's gate-reviewed plan):**
1. The repoint compares server, tool and arguments exactly; the name's letter case is part of the natural key (`RefOf`), so a case-only change is the same row and keeps `CreatedAt`.
2. `CheckRun` rows are kept on a repoint (they record what ran; AD-27 purges them as usual). Coverage ignores them through `CreatedAt`.
3. A `source` row named "Mailbox" written before this story is left alone: 22.5 is unreleased, so no install has one.
4. The mailbox in "I checked" is matched as `entry = ENTRYMAILBOX` on a non-source row, the same test `Verdict` L607 already uses, so no `kind` value is added and AD-18's `kind` sentence stands.

**ENTRYMAILBOX's renderings (Planner ~13:20Z item 4):**
1. `digest.checked`/`digest.checkedQuiet` "I checked {checked}": sentence. **Changes** to "the mailbox".
2. `checks.notEverything*` "Not everything: {whatFailed}.": sentence. **Changes** to "the mailbox".
3. The coverage lines and the digest lead (`digest.passed`, `digest.notChecked*` {entry}): labels. Unchanged.
4. The check rows on the page and in Telegram (`Render` rows' `entry`): labels. Unchanged.
5. `Verdict`'s mailbox-only test (L607) and the stored `Named`: logic and data. Unchanged.

**Integration (Rule 1):**
- Consumes: 22.5's source rows, `Watch.Ops.SetSource`, `Checks.Coverage`'s source branch; 35.1's catalog keys.
- Consumed-by: 22.11 (its baseline rule reads the moved `CreatedAt`); 21.5 (maps `reserved_name` to 400 `bad_source`, lane C's bullet); 22.12 (the docs).
- In this story, `Checks.Coverage.Build` consumes the moved `CreatedAt` (`TestSourceRepointCountsOnlySince`).

**Extend, don't copy (Rule 2):** the reserved-name check extends `OnSetSource`'s name step; `EarlierRun` is extended in place; the repoint extends `SetSource`'s existing-row path.

**Contended edits:** `Mcp/Ops.cls` (one inserted check in `OnSetSource`, one appended parameter); `Checks/Coverage.cls` (`WatchRow` L307-314 and `EarlierRun`); `Digest/Process.cls` (L517, L527). 21.5 (lane C) shares no file.

**Ledger inbox (Rule 17).** DW-1325, DW-1327 and DW-1328 are routed to this story at the split (re-owned from 22.11 by the lead); all three are addressed here. DW-1326 is resolved.

**Spine updates (Rule 20), applied by the lead or the review:**
1. **AD-18, the digest bullet's `stale` clause**, amended to: "`stale` when its latest run is before the span, except that a source takes its latest run at or after its `CreatedAt` as current when that run is within max(the window, its interval plus 180 s) of the window's end [AMENDED 2026-11-14, Story 22.13, Contest Planner rulings ~09:40Z and ~13:20Z Nov 14 (DW-1327); it read "`stale` when its latest run is before the span"]". In the Part A record, "it is stale after the interval plus 180 s" gains "(DW-1327)".
2. **AD-18, the source row:** "a repoint (server, tool or arguments) moves `CreatedAt` to the repoint, so coverage and 22.11's baseline start afresh; `CheckRun` rows are kept (DW-1328, Story 22.13)"; and McpOps refuses a source named like the mailbox with `reserved_name` (DW-1325).
3. **AD-28 / the digest bullet:** the connected mailbox reads "the mailbox" inside the digest's sentences and "Mailbox" as a label (Planner ~12:45Z and ~13:20Z item 4).

## Verification

Each `ci/iris.sh` and `ci/warm.sh` call carries the lane's variables:
`OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-d" OCUTALON_TEST_WEB_PORT=52804 OCUTALON_LOCK_OWNER='epic=22 stage=implement'`.
- Warm runs add `OCUTALON_WARM=1 OCUTALON_RUN_TAG=e22s13iw`; fresh runs use `OCUTALON_RUN_TAG=e22s13i`.
- Run one test class per foreground call. Each must finish inside about 150 s (this harness moves longer calls to the background).
- Never two `iris_execute_tests` calls in one message. Pass `server` `ocutalon-slot-d` and `namespace` `OCUTALON` on every IRIS MCP call (read-only lookups).

**Commands:**
- (once) `ci/warm.sh status`, then `OCUTALON_RUN_TAG=e22s13iw ci/warm.sh up` -- expected: a ready warm stack.
- (loop) Warm, each `ci/iris.sh class <Class>` -- expected: `CLASS … passed`:
  - `OcuTalon.Test.Mcp.SourceSet`
  - `OcuTalon.Test.Digest.Coverage`
  - `OcuTalon.Test.Digest.Compose`
- (once) Warm, each `ci/iris.sh class <Class>` -- expected: passed:
  - `OcuTalon.Test.Mcp.Ops`
  - `OcuTalon.Test.Mcp.SourceSetProduction`
  - `OcuTalon.Test.Watch.Ops`
  - `OcuTalon.Test.Digest.AllClear`
  - `OcuTalon.Test.Digest.EvalCase`
  - `OcuTalon.Test.Digest.TelegramText`
  - `OcuTalon.Test.Msg.Catalog`
- (once) `bash docker/tests/test-boundaries.sh`, `bash docker/tests/test-class-rules.sh`, `bash docker/tests/test-storage.sh` and `bash docker/tests/test-readme.sh`, one per call -- expected: exit 0.
- (once) `OCUTALON_RUN_TAG=e22s13iw ci/warm.sh down` -- also after a failure.

**CI:** no new class, unit, group or area.

**Shared surfaces:**
- McpOps' outcome list (`Test.Mcp.Ops`, `Test.Mcp.SourceSet`);
- `Watch.Ops.SetSource`'s update path (`Test.Watch.Ops`, `Test.Mcp.SourceSet`);
- coverage of a row with no run in the window (`Test.Digest.Coverage` `TestStale`);
- the "I checked" and "Not everything" sentences (`Test.Digest.Compose`, `Test.Digest.EvalCase`, `Test.Digest.AllClear`, `Test.Digest.TelegramText`, any eval golden text naming "the Mailbox").

Standing criterion: every test added or changed passes on a fresh environment, in either order.

**Pinning mutations (Rule 19):**

| Mutation | Test that goes red |
| --- | --- |
| Reserved-name check without the case fold | `TestSetRefusedReservedName` |
| Reserved-name check on the untrimmed name | `TestSetRefusedReservedName` |
| Drop the DW-1327 earlier-run rule | `TestSourceLongIntervalCurrent` |
| Ignore the age limit | `TestSourceLongIntervalStale` |
| Drop the `CreatedAt` bound in `EarlierRun` | `TestSourceEarlierRunBeforeCreatedAt` |
| `REPOINTRESETS` 0 | `TestRepointMovesCreatedAt`, `TestSourceRepointCountsOnlySince` |
| Reset `CreatedAt` on every update | `TestSameTargetKeepsCreatedAt` |
| `"the "_entry` for the mailbox | `TestCheckedListSourceBare`, `TestCheckedListMailboxLower` |
| `whatFailed` from `verdict.named` unchanged | `TestNotEverythingMailboxLower` |

## Auto Run Result

Status: done
Blocking condition: none

Implemented the split of 22.11 as specified:
- DW-1325: `Mcp/Ops.cls` answers `reserved_name` (new `MESSAGESOURCERESERVED`) for the name "Mailbox" in any letter case, after the trim; nothing is written.
- DW-1327: `Checks/Coverage.cls` extends `EarlierRun` (optional CreatedAt bound; returns result, reason, finding) and adds `Current`; a source with no run in the span takes its newest run since CreatedAt as its latest run when it is within max(window, interval x 60 + 180 s) of the window's end; other kinds unchanged.
- DW-1328: `Watch/Ops.cls` adds `REPOINTRESETS = 1`; a changed server, tool or arguments moves CreatedAt to now; interval-only and case-only updates keep it.
- Mailbox sentences: `Digest/Process.cls` adds `MAILBOXINSENTENCE` ("the mailbox") for "I checked" and `whatFailed`; labels unchanged.
- `Data/BackgroundCheck.cls`: doc only.
- Tests: `Test/Mcp/SourceSet.cls` (3 new), `Test/Digest/Coverage.cls` (4 new, `Clean` also deletes source rows, `RunCount` helper), `Test/Digest/Compose.cls` (1 changed, 2 new).

Review: 25 findings from four layers; 2 patched (a loop comment; repoint tests now pin Reported, NextDueAt and the CheckRun row), 1 deferred (empty window end untested), 22 rejected with reasons in the triage log. Follow-up review recommended: false.

Verification (warm stack e22s13iw, torn down): `Test.Mcp.SourceSet`, `Test.Digest.Coverage`, `Test.Digest.Compose` (loop, after the last patch), then `Test.Mcp.Ops`, `Test.Mcp.SourceSetProduction`, `Test.Watch.Ops`, `Test.Digest.AllClear`, `Test.Digest.EvalCase`, `Test.Digest.TelegramText`, `Test.Msg.Catalog` all passed; `test-boundaries.sh`, `test-class-rules.sh`, `test-storage.sh`, `test-readme.sh` exit 0. All nine Pinning mutations were observed red and reverted byte-identical (checksums compared).

Residual risks: the window term of max(window, interval + 180 s) cannot change a result (the earlier run is always before the window's start), so the effective limit is interval x 60 + 180 s; the Planner's wording is kept. The spine updates (AD-18, AD-28) are the lead's.
