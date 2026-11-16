---
title: 'DW-1376: A run that was saved but not applied has an ended line in the incident summary'
type: 'bugfix'
created: '2026-11-16'
status: 'done'
baseline_revision: '5a0038e161575f69b4155c55b45f7147500db11e'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/spec-21-dw-1373-a-suspend-or-resume-that-could-not-be-applied-is-not-reported-as-nothing-changed.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-23-3-name-the-setting-change-behind-an-incident-and-offer-its-rol.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-23-6-write-an-incident-summary-when-an-incident-closes.md'
warnings: []
deferred: []
---

<intent-contract>

## Intent

**Problem (DW-1376, MED, fix-risk low; harvested from 23.3's frontmatter `deferred`):** the incident summary is silent about a fix run that changed a setting and that the production could not apply.
- When the production's update fails after a setting was saved, and the earlier value cannot be put back, the run ends failed with Completed 0, Skipped 0, Unreached 1 and the production's error (23.3, DW-1365). The session and the card read the approved `result.settingSavedNotApplied`.
- `Watch.SettingCause.SummaryRunKey` (`Watch/SettingCause.cls:377-382`) returns "" for Completed 0 with Unreached above 0 (L379). `Watch.Summary.RunEvents`' setting branch (`Watch/Summary.cls:212-216`) then writes no ended line. `summary.settingNotChanged` would have been false there, and no summary text for "changed but not applied" was approved.
- DW-1373 (on this branch, `d7e7e925a`) gave a suspend or resume the same end, and the same silence: `RunEvents`' item branch quits before its key for such a run (`Watch/Summary.cls:207`).
- So the summary of such an incident shows "OcuTalon asked for approval ...", the approval and "the fix started", and then nothing about what happened.

**Ruling (Contest Planner, 2026-11-15, `prompts/story-234-rulings-20261115.md`, "23.3 follow-ups"; ledger DW-1376 `routed` 2026-11-15T14:11:08Z):** "DW-1376: APPROVED with new text, summary.settingSavedNotApplied: "{time}: {setting} on {target} was changed, but the production couldn't apply it." Pin it on the restore-failed path." It is not a 23.3 re-push.

**Approach:**
- Add the approved key to the Watch catalog, verbatim, with the slots of the other setting summary lines: `time` (time), `setting` (text), `target` (text).
- **Setting runs:** `SummaryRunKey` returns the new key for Completed 0 with Unreached above 0, instead of "". The setting branch of `RunEvents` already fills `setting` and `target` from the request's dry run (`SettingCause.Names`: the dry run's `field` and `item`), so it needs no change.
- **Item runs:** `RunEvents`' item branch writes the new key for the same counts, instead of quitting. The slots are `setting` = the kind's `ENABLEDSETTING` ("Enabled", DW-1373), `target` = the request's `item` parameter. These are the slots that `Watch.Notice.ResultSlots` already gives the item run's result line. It reads: "{time}: Enabled on OrdersForReview was changed, but the production couldn't apply it."
- A run whose restore worked is `refused`, so it could not start (Completed 0, Unreached 0). It keeps `summary.settingNotChanged` or `summary.itemNotChanged`, which is true. No other end changes.

## Boundaries & Constraints

**Always:**
- **Footprint** (all Lane A; lane C makes the edits under the run's DW-1376 assignment, Veto item 2):
  - `src/ocutalon/cls/OcuTalon/Msg/Catalog/Watch.cls`: the new entry.
  - `src/ocutalon/cls/OcuTalon/Watch/SettingCause.cls`: a new parameter, and `SummaryRunKey` with its doc.
  - `src/ocutalon/cls/OcuTalon/Watch/Summary.cls`: `RunEvents`' item branch, the `RunEvents` doc, and the class doc's item clause (L12).
  - Tests: `src/ocutalon/cls/OcuTalon/Test/Msg/Catalog.cls`, `src/ocutalon/cls/OcuTalon/Test/Watch/Summary.cls` and `src/ocutalon/cls/OcuTalon/Test/Fix/ItemKinds.cls`.
  - This spec.
- The approved text is used verbatim, in one entry: "{time}: {setting} on {target} was changed, but the production couldn't apply it." The apostrophe is ASCII 39, as in `result.settingSavedNotApplied`. ObjectScript stays ASCII. Comments state the contract, not review history.
- The item line's setting name comes from the kind's parameter, never a literal in `Watch.Summary`: `$Parameter(class, "ENABLEDSETTING")`, as the branch already reads `ENABLE`.
- The condition for the new line is the one that today suppresses the line: `(+run.Completed = 0) && (+run.Unreached > 0)`, in both places.
- Every existing test passes, with only the two "no ended line" methods changed to "this ended line". Their negative assertions (no `summary.settingNotChanged`, `summary.settingRestored`, `summary.itemNotChanged` or `summary.itemSuspended`) stay.

**Never:**
- Change the wording of the approved key, add another key, or change any other catalog entry or slot type.
- Change `Fix.Executor`, `Fix.Kind.*`, `Watch.Notice`, `IncidentManager`, the FixRun or FixResult classes, any `web/` file, `EXPERIENCE.md` or `docs/`.
- Change the end line of any other run: done, skipped, could not start, interrupted, not ended, message kinds or contact kinds.
- Delete, skip or weaken a test.

## I/O & Edge-Case Matrix

"Not applied" means a FixRun that ended (EndedAt set, Interrupted 0) with Completed 0 and Unreached above 0. Today only a setting or item kind's `notapplied` entry gives this: the executor's restore failed (23.3, DW-1373). The run's line sits at its EndedAt in the timeline.

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| 1 Setting run not applied | `rollback_setting` or `undo_rollback`, request failed; FixRun Completed 0, Skipped 0, Unreached 1, Reason the production's error; dry run `{"item": "OrdersFromPartner", "field": "ZzFixtureNote", ...}` | The summary has the requested line, the answer, `summary.fixStarted`, then `summary.settingSavedNotApplied` with time = EndedAt, setting = `ZzFixtureNote`, target = `OrdersFromPartner`: "{time}: ZzFixtureNote on OrdersFromPartner was changed, but the production couldn't apply it." No `summary.settingNotChanged`, `settingRestored` or `rollbackUndone`. | none |
| 2 Item run not applied | `suspend_item` or `resume_item`, request failed; FixRun as in row 1; parameters `{"item": "OrdersForReview"}` | `summary.settingSavedNotApplied` with time = EndedAt, setting = `Enabled`, target = `OrdersForReview`: "{time}: Enabled on OrdersForReview was changed, but the production couldn't apply it." No `summary.itemNotChanged`, `itemSuspended` or `itemResumed`. | none |
| 3 Restore OK | The update failed and the earlier value or flag was stored again and applied: entry `refused`, so the run could not start (Completed 0, Skipped 0, Unreached 0) | Unchanged: a setting run ends with `summary.settingNotChanged`, an item run with `summary.itemNotChanged`. No not-applied line. | none |
| 4 Done | Completed 1 | Unchanged: `summary.settingRestored`, `summary.rollbackUndone`, `summary.itemSuspended` or `summary.itemResumed`. | none |
| 5 Skipped | Completed 0, Skipped 1, Unreached 0 (changed since the dry run, or item already in the wanted state) | Unchanged: `summary.settingNotChanged` or `summary.itemNotChanged`. | none |
| 6 Interrupted, or not ended | Interrupted above 0, or EndedAt "" | Unchanged: `summary.fixInterrupted`, or only `summary.fixStarted`. Both are decided before the kind branches. | none |
| 7 Setting request without names | A setting request whose dry run has no `field` or `item` (`SettingCause.Names` gives 0) | Unchanged: no ended line, as for every end of such a request today. | none |
| 8 Message and contact kinds | Any counts, Unreached included (message copies) | Unchanged: `summary.fixEnded` or the partner lines. The new code sits only in the setting and item branches. | none |
| 9 Incidents closed before the change | `Incident.Summary` stored without the line | Unchanged: the stored parts render as before. Nothing rebuilds a stored summary. | none |

</intent-contract>

## Code Map

Line numbers are at the baseline `40f087aa1` (DW-1373's head plus its plan log).

- `Msg/Catalog/Watch.cls`: the summary keys of the setting kinds L1223-1266 (`summary.settingNotChanged` L1259-1266, the model), `result.settingSavedNotApplied` L1268-1276 (the result text that this key's wording follows), the item summary keys L936-958.
- `Watch/SettingCause.cls`:
  - Class doc L13 ("the summary keys ... which Notice and Summary call").
  - `KEYSAVEDNOTAPPLIED` L47 and the `KEYSUMMARY*` parameters L49-57.
  - `Names` L355: the setting and target from the dry run.
  - `SummaryRequestKey` L371.
  - `SummaryRunKey` L376-382: its doc L376, the not-applied line L379, and `KEYSUMMARYNOTCHANGED` L380.
- `Watch/Summary.cls`:
  - Class doc L12, the item clause "(none for a run that stored the flag and could not apply it)".
  - `RunEvents` doc L182-184 and the method L185:
    - the interrupted test L201-204;
    - the item branch L205-211 (the item L206, the not-applied `Quit` L207, the key L208, its `Event` L209);
    - the setting branch L212-216 (`SummaryRunKey` L213, and `Names` and `Event` L214).
  - `Event` L261 (a line without a UTC time is left out).
- `Fix/Kind/SuspendItem.cls` (read only): `TARGETTYPE` "item" L21, `ENABLE` L30, `ENABLEDSETTING` "Enabled" L33 (DW-1373). `ResumeItem` extends it, and they are the only item kinds.
- `Watch/Notice.cls` (read only): `ResultSlots` maps an item run's `result.settingSavedNotApplied` to setting `SuspendItem.#ENABLEDSETTING` and target the item (DW-1373). The summary line uses the same pair.
- `Test/Msg/Catalog.cls`:
  - The Watch count comments L91-99, the count L100, the exact-list label L102.
  - XData `Keys`: `"summary.settingNotChanged"` L1416, then `"result.settingSavedNotApplied"` L1417.
  - XData `Fixtures`: `summary.settingNotChanged` L1923, `result.settingSavedNotApplied` L1924.
  - The tests that sweep every key: `TestEntries` L74, `TestEveryKeyOnEveryChannel` L136, `TestTypography` L561, `TestWebWording` L499 (the new key has no `web`, so the list of eighteen keys is unchanged), and `TestLocalInstallEveryKey` L795.
- `Test/Watch/Summary.cls`:
  - Class doc bullets L40-41.
  - `TestSettingLines` L816 (the setting-run model).
  - `TestSettingSavedNotAppliedLine` L860-882 (doc L860-862).
  - `TestItemSavedNotAppliedLine` L883-904 (doc L883-884).
  - Helpers: `T` L922, `Request` L946, `Link` L954, `Keys` L1028, `Slots` L1040 (the first part with the key).
- `Test/Fix/ItemKinds.cls`:
  - Class doc bullets L16-17 (`TestSettingNotApplied`) and L22-23 (`TestItemNotApplied`).
  - `TestSettingNotApplied` L445-515: the not-applied half starts at the second `..Fixture` call.
  - `TestItemNotApplied` L674-721.
  - `ITEM` = `OrdersForReview` L36.
  - Helpers: `Handle` L763, `Request` L805 (it does not set the incident's `RequestRefs`).
  - `Test/Watch/Case.cls`: `Fixture` L932 (FirstAt set, no ItemNoun, so `Notice.Common` uses the code noun) and `Runs` L1875.
- Key-set pins checked, none of which change:
  - `web/scripts/catalog.mjs` `LISTED_KEYS` holds no `summary.*` key, and `web/src/app/msg/catalog.ts` holds none (count 0). So `catalog.test.mjs`'s counts (78 page texts, 22 result keys) and `--check` are untouched.
  - `web/scripts/ux-strings.test.mjs` holds only page strings. The summary reaches the page as server-rendered lines (`history-page.ts` `summaryLines`; `Watch.Summary.Text` in the three `*Out` operations).
  - `EXPERIENCE.md`, `docs/` and the architecture spine name no `summary.setting*` key or text.

## Tasks & Acceptance

**Task 0 (measure first, on a lane-C warm throwaway, before any product edit; record each result under `## Verification`; never a dev slot, Rule 21):**
1. **Baseline.** At the baseline, run `OcuTalon.Test.Watch.Summary:TestSettingSavedNotAppliedLine`, `OcuTalon.Test.Watch.Summary:TestItemSavedNotAppliedLine` and `OcuTalon.Test.Msg.Catalog` warm, one call each. Record that each passes.
2. **The stored run of the restore-failed path, and the summary it gives today.** Use a scratch class (e.g. `ZzScratch.Dw1376`) in your scratchpad, loaded into the throwaway only and never committed, or a scratch copy of `TestItemNotApplied` run warm. After the not-applied `Handle` of `TestItemNotApplied` (suspend_item, CarryIs `notapplied` "The update timed out"), record:
   - `Case.Runs(incident)`: one FixRun, with its Completed, Skipped, Unreached, Interrupted, Reason and whether EndedAt is a UTC time (expect 0, 0, 1, 0, "The update timed out", yes);
   - with the incident's `RequestRefs` set to the request, `Watch.Summary.Build(row, "dismiss", NowUtc, 0, .sc)`: the status (expect OK) and the parts' keys (expect `summary.title`, `summary.requestedSuspend`, `summary.approved`, `summary.fixStarted`, `summary.closedDismiss` ..., with no ended line).
   - Do the same for `TestSettingNotApplied`'s not-applied half (rollback_setting): expect the same counts, and keys with `summary.requestedRollback` and no ended line.
   - If `Build` errs on the `Case.Fixture` incident, record the error, and either give the incident the field it needs through `Fixture`'s `fields`, or drop the ItemKinds half of AC 3 and say so in `## Verification`. The `Test.Watch.Summary` pins (AC 1, AC 2) carry the behaviour either way.
3. **The Watch count at implement time.** Run `git log --oneline <feature head> -- src/ocutalon/cls/OcuTalon/Test/Msg/Catalog.cls`, and record whether OCT-epic23's `summary.partnerMaySent` (23.13 rework, DW-1416) is on feature yet.
   - If it is not, the count goes 145 to 146 (the tasks below).
   - If it is (after an integrate-forward of this branch), the count goes 146 to 147, and the comment says "takes the Watch count to 147".

**Execution:**
- [ ] `Msg/Catalog/Watch.cls`: insert after the `summary.settingNotChanged` entry (after L1266), before `result.settingSavedNotApplied`:
  ```
   "summary.settingSavedNotApplied": {
    "text": "{time}: {setting} on {target} was changed, but the production couldn't apply it.",
    "slots": {
     "time": "time",
     "setting": "text",
     "target": "text"
    },
    "source": "DW-1376 (Story 23.3 and DW-1373 follow-up), Public Text approved by the Contest Planner 2026-11-15 (23.3 follow-ups ruling)"
   },
  ```
- [ ] `Watch/SettingCause.cls`:
  - After `KEYSUMMARYNOTCHANGED` (L57), add a blank line and `Parameter KEYSUMMARYSAVEDNOTAPPLIED = "summary.settingSavedNotApplied";`.
  - `SummaryRunKey` L379 becomes `If (+run.Completed = 0) && (+run.Unreached > 0) Quit ..#KEYSUMMARYSAVEDNOTAPPLIED`.
  - Its doc (L376) becomes: "/// The key of the line for the end of a setting kind's run: summary.settingSavedNotApplied when the setting was saved and the production could not apply it and the earlier value could not be put back (Completed 0, Unreached above 0), summary.settingNotChanged when the run changed nothing else, and the restore or the undo when it changed the setting. Watch.Summary gives an item kind's run of the same end the same key (setting Enabled, target the item)."
- [ ] `Watch/Summary.cls`:
  - `RunEvents`' item branch: replace L207 (`If (+run.Completed = 0) && (+run.Unreached > 0) Quit`) with:
    ```
    		If (+run.Completed = 0) && (+run.Unreached > 0) {
    			Do ..Event(.timeline, .seq, run.EndedAt, ##class(OcuTalon.Watch.SettingCause).#KEYSUMMARYSAVEDNOTAPPLIED, {"time": (run.EndedAt), "setting": ($Parameter(class, "ENABLEDSETTING")), "target": (item)})
    			Quit
    		}
    ```
  - Class doc L12: replace "(none for a run that stored the flag and could not apply it)" with "(summary.settingSavedNotApplied, with the setting Enabled and the item as the target, for a run that stored the flag and could not apply it)".
  - `RunEvents` doc L182-183: "(suspended, resumed or not changed)" becomes "(suspended, resumed, not changed, or changed and not applied)". Add after the first sentence: "A run of a setting kind ends with the key of Watch.SettingCause SummaryRunKey, the setting and the item of its dry run."
- [ ] `Test/Msg/Catalog.cls`:
  - After the comment L99, add: `// DW-1376 (Contest Planner ruling 2026-11-15, "23.3 follow-ups"): summary.settingSavedNotApplied takes the Watch count to 146.` Use the same tab indent as L99.
  - L100: `145` becomes `146` in the value and in the label. L102: "its 145 keys" becomes "its 146 keys".
  - XData `Keys`: insert `  "summary.settingSavedNotApplied",` after `"summary.settingNotChanged",` (L1416).
  - XData `Fixtures`: insert after the `summary.settingNotChanged` fixture (L1923):
    ` "summary.settingSavedNotApplied": {"slots": {"time": "2026-10-16T18:12:00Z", "setting": "TargetConfigName", "target": "OrdersFromPartner"}, "text": "14:12 ET: TargetConfigName on OrdersFromPartner was changed, but the production couldn't apply it."},`
  - The class doc's counts (L3: 157 and 141) and the label "254 keys" (L140) are stale before this change and are left as they are, so that the merge with OCT-epic23 stays small. The asserts compare the lists.
- [ ] Tests (below), each with its header bullet in the class doc changed or added.
- [ ] This spec: `## Verification` (Task 0 and the mutation lines).

**Tests:**
- `Test/Watch/Summary.cls` (warm; fixture rows through the probe, as today):
  - `TestSettingSavedNotAppliedLine` (AC 1):
    - Set `ended = ..T(-5700)` and use it as the FixRun's EndedAt.
    - Add an `undo_rollback` request (state failed, raised `..T(-5000)`, answered `..T(-4900)`, the undo dry run of `TestSettingLines`). Its FixRun is StartedAt `..T(-4800)`, EndedAt `..T(-4700)`, Completed 0, Skipped 0, Unreached 1, Reason "The update timed out". Link both requests.
    - Keep the existing four assertions. With the second request, "summary.requestedRollback" is still 1 and "summary.fixStarted" becomes 2.
    - Add:
      - `$Length(keys, "summary.settingSavedNotApplied") - 1` is 2: "each run that saved the setting and could not apply it ends with summary.settingSavedNotApplied";
      - `keys [ "summary.fixStarted,summary.settingSavedNotApplied"`: "the rollback's line follows its started line";
      - `$Length(keys, "summary.rollbackUndone") - 1` is 0: "and the undo is not reported as undone";
      - `..Slots(row, "summary.settingSavedNotApplied")` gives `time|setting|target` = `ended_"|ZzFixtureNote|OrdersFromPartner"`: "the line names the setting and the item, at the run's end";
      - `Watch.Summary.Text(incident, "web", .sc)` is OK, and the text contains `": ZzFixtureNote on OrdersFromPartner was changed, but the production couldn't apply it."`: "and reads as ruled".
    - The method doc reads: "... (Completed 0, Unreached 1, Skipped 0), for a rollback and an undo, ends with summary.settingSavedNotApplied, which names the setting and the item, and with no summary.settingNotChanged, settingRestored or rollbackUndone. mutation: SummaryRunKey's not-applied line made Quit "" (no line), or taken out (summary.settingNotChanged)."
  - `TestItemSavedNotAppliedLine` (AC 2):
    - Set `ended = ..T(-5700)` for the suspend's run.
    - Add a `resume_item` request on `OrdersForReview` (state failed, raised `..T(-5000)`, answered `..T(-4900)`, dry run `{"item": "OrdersForReview", "before": "disabled", "after": "enabled"}`). Its run is `..T(-4800)` to `..T(-4700)`, Completed 0, Unreached 1, Reason "The update timed out". Link both.
    - Keep the existing assertions, and add "and no summary.itemResumed".
    - Add:
      - `$Length(keys, "summary.settingSavedNotApplied") - 1` is 2;
      - `keys [ "summary.fixStarted,summary.settingSavedNotApplied"`;
      - the first part's `time|setting|target` is `ended_"|Enabled|OrdersToWarehouse"` ("the item's setting is Enabled and the target is the item");
      - the web text contains `": Enabled on OrdersToWarehouse was changed, but the production couldn't apply it."` and `": Enabled on OrdersForReview was changed, but the production couldn't apply it."`.
    - The method doc changes to match. Its mutation is the item branch's new block taken back to `Quit`, or the block taken out (summary.itemNotChanged).
  - Class doc bullets L40-41: "has no ended line" becomes "ends with summary.settingSavedNotApplied (DW-1376)", and the item bullet also says "(setting Enabled, target the item), for a suspend and a resume". Add "and an undo" to the setting bullet.
- `Test/Fix/ItemKinds.cls`: the restore-failed path joined to the summary (AC 3). These are the canned tests that run the real `Finish` through FixExecutor's handler. They run warm after a production restart, as in DW-1373.
  - A private helper `SavedNotAppliedLine(incident As %String, ref As %String) As %String`. Its doc: "The incident's summary line of the run of the request, as Watch.Summary builds it from the stored rows with the request as the incident's only request, rendered for the phone. "" when the summary has no summary.settingSavedNotApplied part." It:
    - opens the incident, sets `RequestRefs = ref` and saves it, asserting OK ("the incident names the request");
    - calls `##class(OcuTalon.Watch.Summary).Build(row, "dismiss", ##class(OcuTalon.Data.Time).NowUtc(), 0, .sc)`, asserting the status ("the summary is built from the stored run");
    - walks `summary.parts`, and for the part keyed `summary.settingSavedNotApplied` returns `##class(OcuTalon.Msg.Catalog).Render(part.key, part.slots.%ToJSON(), "phone", .sc)`.
  - `TestItemNotApplied`: after the existing asserts, `$Piece(..SavedNotAppliedLine(incident, ref), ": ", 2, *)` equals "Enabled on OrdersForReview was changed, but the production couldn't apply it.": "the summary ends the run with summary.settingSavedNotApplied, as ruled". The test sets the online-demo flag 0, so the time has no " ET", and a time of the same day has no ": " of its own.
  - `TestSettingNotApplied`: the same after the not-applied half, with "ZzFixtureNote on OrdersFromPartner was changed, but the production couldn't apply it.". Use that half's `incident` and `ref`.
  - Each method doc gains: "and the incident summary, built from the stored run, ends it with summary.settingSavedNotApplied (DW-1376)". The class doc bullets L16-17 and L22-23 gain the same clause.
- `Test/Msg/Catalog.cls` (AC 4): the new key in `Keys` and `Fixtures`, and the count. `TestEntries`, `TestEveryKeyOnEveryChannel`, `TestTypography`, `TestWebWording` and `TestLocalInstallEveryKey` then cover it with no new method.

**Acceptance Criteria:**
1. Given a setting run (rollback or undo) that saved the setting and could not apply it (Completed 0, Unreached 1), when its incident closes, then the summary has `summary.settingSavedNotApplied` at the run's end, with the setting and the item of the dry run. It reads "{time}: ZzFixtureNote on OrdersFromPartner was changed, but the production couldn't apply it.", and there is no not-changed, restored or undone line.
   - mutation: `SummaryRunKey`'s not-applied line made `Quit ""` again -> `TestSettingSavedNotAppliedLine` red ("each run ... ends with summary.settingSavedNotApplied").
   - mutation: `SummaryRunKey`'s not-applied line taken out -> `TestSettingSavedNotAppliedLine` red ("and no summary.settingNotChanged"; the 23.3 mutation, kept).
2. Given a suspend or resume run that stored the flag and could not apply it, when its incident closes, then the summary has `summary.settingSavedNotApplied` with the setting Enabled and the item as the target: "{time}: Enabled on OrdersForReview was changed, but the production couldn't apply it."
   - mutation: the item branch's new block made `If (+run.Completed = 0) && (+run.Unreached > 0) Quit` again -> `TestItemSavedNotAppliedLine` red.
   - mutation: the block taken out -> `TestItemSavedNotAppliedLine` red ("and no summary.itemNotChanged"; DW-1373's mutation, kept).
   - mutation: `$Parameter(class, "ENABLEDSETTING")` replaced by `item`, and `(item)` by `$Parameter(class, "ENABLEDSETTING")` (the slots swapped) -> `TestItemSavedNotAppliedLine` red ("the item's setting is Enabled and the target is the item").
3. Given the restore-failed path through the real executor handler and `Finish` (canned Check and Carry), when the summary is built from the stored FixRun, then the run ends with the new line, for an item kind and a setting kind.
   - mutation: the item branch's new block made `Quit` -> `TestItemNotApplied` red.
   - mutation: `SummaryRunKey`'s not-applied line made `Quit ""` -> `TestSettingNotApplied` red.
4. Given the catalog, then the Watch class holds exactly its 146 keys (147 after OCT-epic23's key, Task 0 item 3). The new key renders the fixture text on every message channel and on the web, and has clean ASCII and no web form.
   - mutation: the new catalog entry taken out -> `Test.Msg.Catalog` red ("Watch holds exactly its 146 keys", and the fixture coverage of `TestEveryKeyOnEveryChannel`).
   - mutation: the entry's "but " taken out of its text -> `TestEveryKeyOnEveryChannel` red (the fixture text), and `TestSettingSavedNotAppliedLine` red ("and reads as ruled").
5. Given a run whose restore worked (could not start), a done or skipped run, an interrupted run or one that has not ended, then its summary line is as before. `TestKindLines`, `TestSettingLines` and `TestRunEdges` pass unchanged, and so do `Test.Watch.Lifecycle` and `Test.Watch.SettingValues`, which read setting and item summary keys.

## Design Notes

**One key for both kinds.** The Planner approved one text with `{setting}` and `{target}`. DW-1373 already renders the item run's result line through `result.settingSavedNotApplied` with setting `Enabled` and target the item (`Notice.ResultSlots`). Using the same slots here keeps the session, the card and the summary saying the same thing about the same run:
- session: "Enabled on OrdersForReview was changed, but the production couldn't apply it: {reason}. Ask me to check the item before you try again.";
- summary: "{time}: Enabled on OrdersForReview was changed, but the production couldn't apply it."

**Truthfulness for an item run.** "Enabled" is the IRIS name of the item's setting, the one the Management Portal shows. "Was changed" is true: the stored flag, in the definition or in the System Default Setting row that overrides it, was changed, logged and audited. "Couldn't apply it" is true: the update failed. When the restore's store worked and only its update failed, the stored flag is the earlier one again. The same wording was accepted for the result line in that sub-case (23.3 review Blind 2; DW-1373 review Auditor 1, `by-design`). The Planner approved this text for this path ("Pin it on the restore-failed path"). The summary is a record of the run, and the session's line for the same run says "Ask me to check the item". So no PLANNER REPORT is needed.

**Where the key lives.** The setting summary keys live in `Watch.SettingCause`, and DW-1373 already has `Watch.Notice` read `SettingCause.#KEYSAVEDNOTAPPLIED` for an item run. The item branch of `Watch.Summary` reads `SettingCause.#KEYSUMMARYSAVEDNOTAPPLIED` the same way, so the key string is written once in product code.

**What the slots are.**
- A setting run takes `setting` and `target` from `SettingCause.Names` (the dry run's `field` and `item`), as its other lines do. A request without them gets no line (matrix 7), as today.
- An item run takes `target` from the request's `item` parameter, the value the branch's other lines use. `SuspendItem.CheckParameters` requires it (PARAMETERS "item"), so it is never empty for a stored request. A missing one would affect `summary.itemSuspended` the same way today. No guard is added.

**Why the ItemKinds join.** `Test.Watch.Summary` models the FixRun by hand. The Planner asked for the pin on the restore-failed path, so AC 3 builds the summary from the FixRun that `Fix.Executor.Finish` itself stored for a `notapplied` entry. DW-1373's live tests (`TestItemUpdateFailureNotApplied`) and 23.3's (`Test.Watch.Rollback` `TestUpdateFailureNotApplied`) pin `InProduction` giving `notapplied` on a real failed restore. Together the chain is pinned from the IRIS update failure to the summary line. No new seam.

**Merge with OCT-epic23.** The 23.13 rework (DW-1416, unmerged at plan time) adds `summary.partnerMaySent` and also takes the Watch count from 145 to 146. It edits the same lines of `Test.Msg.Catalog` (L99-102) and line 12 of `Watch.Summary`'s class doc. Whichever branch reaches feature second resolves at its integrate-forward:
- keep both comment lines;
- set the count and both labels to 147, with that branch's comment saying "to 147";
- keep both keys in `Keys` and `Fixtures` (different places in each list, so no textual conflict);
- on line 12, keep this change's item clause and 23.13's partner clause.

This is the "plain union at the integrate-forward" that the count comments record for earlier stories.

**AD:** none. AD-32 holds: the summary stays parts of catalog keys, rendered only by `Msg.Catalog`. AD-15's summary sentence lists no ended keys.

**Ledger:** DW-1376 (this spec). Its status line is recorded at merge, through `ledger.sh append`, per the run's DW process.

## Veto items

| # | Gate item | What | Recommendation |
|---|-----------|------|----------------|
| 1 | (a) New public text | One new catalog key, `summary.settingSavedNotApplied`, with the Planner's approved text verbatim: "{time}: {setting} on {target} was changed, but the production couldn't apply it." Its slots are time (time), setting (text) and target (text), as the other setting summary lines. A setting run fills setting and target from its dry run ("ZzFixtureNote on OrdersFromPartner"). An item run fills setting Enabled and target the item: "{time}: Enabled on OrdersForReview was changed, but the production couldn't apply it." No other text is added or changed. | Approve (already approved verbatim, ruling of 2026-11-15, "23.3 follow-ups"). |
| 2 | (b) Cross-lane edits | None outside Lane A: `Msg.Catalog.Watch`, `Watch.SettingCause`, `Watch.Summary`, `Test.Msg.Catalog`, `Test.Watch.Summary` and `Test.Fix.ItemKinds`. No `web/`, `docs/` or `EXPERIENCE.md` file changes: the summary is rendered on the server, and `web/scripts/catalog.mjs` lists no `summary.*` key. Lane C makes the edits under the run's DW-1376 assignment. Overlap: OCT-epic23 (23.13 rework, unmerged) edits the same count lines of `Test.Msg.Catalog` and line 12 of `Watch.Summary`'s doc. The second to merge takes the count to 147 (Design Notes). | Grant. |
| 3 | (c) Stored data or schema | None. No class, property or storage change. A summary stored from now on holds one more part for such a run. Summaries stored before keep their parts and render as before. | Approve, with no migration. |
| 4 | (d) Architecture change | None. AD-32 and AD-15 stay true. | Approve with no AD change. |
| 5 | (e) Product behaviour change | The incident summary now has an ended line for a setting run (rollback or undo) or an item run (suspend or resume) that was saved and that the production could not apply, the restore having failed. Until now it had none. The line sits at the run's end time and reads "{time}: {setting} on {target} was changed, but the production couldn't apply it." No other run's line changes. A run whose restore worked keeps "was not changed". | Approve. |

## Public text

New, approved verbatim (Contest Planner ruling 2026-11-15, `prompts/story-234-rulings-20261115.md`, "23.3 follow-ups"):
- `summary.settingSavedNotApplied`: "{time}: {setting} on {target} was changed, but the production couldn't apply it."
  - Setting run: "14:12 ET: TargetConfigName on OrdersFromPartner was changed, but the production couldn't apply it." (catalog fixture, online demo)
  - Item run: "{time}: Enabled on OrdersForReview was changed, but the production couldn't apply it."

Unchanged, read for consistency: `result.settingSavedNotApplied`, `summary.settingNotChanged` and `summary.itemNotChanged`.

## Verification

Use a lane C throwaway only (Rule 21), never a dev slot. Set these on every `ci/iris.sh` and `ci/warm.sh` call: `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=21 stage=<stage>'`.
- Warm runs add `OCUTALON_WARM=1 OCUTALON_RUN_TAG=<warm tag>`. Fresh runs leave `OCUTALON_WARM` unset.
- One test class (or `Class:Method`) per foreground call, `timeout: 600000`, each under about 3 minutes. Never run two test calls in one message.

**Commands:**
- (once) `ci/warm.sh up` with the warm tag, then Task 0 items 1 and 2 before any product edit. Item 3 is a git check.
- (loop) Warm, each expected to pass:
  - `ci/iris.sh class OcuTalon.Test.Watch.Summary:TestSettingSavedNotAppliedLine`, then `:TestItemSavedNotAppliedLine`;
  - `ci/iris.sh class OcuTalon.Test.Msg.Catalog`;
  - after a production restart, `ci/iris.sh class OcuTalon.Test.Fix.ItemKinds:TestItemNotApplied`, then `:TestSettingNotApplied`.
- (once) Warm, whole classes, each expected to pass: `OcuTalon.Test.Watch.Summary`, `OcuTalon.Test.Watch.SettingValues`, `OcuTalon.Test.Watch.Lifecycle`.
- (once) Fresh, each expected to pass: `OcuTalon.Test.Msg.Catalog`, `OcuTalon.Test.Watch.Summary`, `OcuTalon.Test.Fix.ItemKinds` (whole class, or split by method).
- (once) `node web/scripts/catalog.mjs --check` exits 0 (the page's catalog module is unchanged), and `node --test web/scripts/catalog.test.mjs` passes.
- (once) `bash docker/tests/test-boundaries.sh`, then `bash docker/tests/test-class-rules.sh`, one per call: each exits 0.
- (once) `git diff --name-only 40f087aa1` lists only the footprint files. No added line holds a non-ASCII character or an absolute local path.
- (once, at the end, also after a failure) `ci/warm.sh down` with the warm tag.

**Mutations (Rule 19):**
- Write one `mutation:` line per mutation under AC 1 to 4, as `mutation: <change> -> <test that went red>`.
- Revert each byte for byte (`cmp` against a copy taken before it), and check that `git status --short` and `git diff --stat` are as before.

**Task 0 records** (lane C warm throwaway, tag e21dw1376iw; scratch class `ZzScratch.Dw1376` extending `Test.Fix.ItemKinds`, loaded into the throwaway only and deleted from it, never in the tree):
1. Baseline, warm, one call each, before any product edit: `OcuTalon.Test.Watch.Summary:TestSettingSavedNotAppliedLine` passed, `:TestItemSavedNotAppliedLine` passed, `OcuTalon.Test.Msg.Catalog` passed.
2. The stored run and the summary today, through the real handler and `Finish` with the canned Check and Carry of `TestItemNotApplied` and `TestSettingNotApplied`'s not-applied half, with the incident's `RequestRefs` set to the request:
   - `Case.Runs(incident)`: one FixRun, `total` 1, `resent` 0, `completed` 0, `skipped` 0, `interrupted` 0, `unreached` 1, `reason` "The update timed out", `endedAt` a UTC time (as expected), for `suspend_item` and for `rollback_setting`.
   - `Watch.Summary.Build(row, "dismiss", NowUtc, 0, .sc)` on the `Case.Fixture` incident: status OK for both (no fallback to `Fixture`'s `fields` and no dropped half of AC 3 was needed). Item keys: `summary.title,summary.firstFailure,summary.requestedSuspend,summary.fixStarted,summary.closedDismiss,summary.approved,summary.messages,summary.cost`. Setting keys: the same with `summary.requestedRollback`. Neither has an ended line (the defect).
3. The Watch count at implement time: after `git fetch -q origin`, `git log origin/feature/OCT_OcuTalon_MVP..origin/OCT-epic23 -- src/ocutalon/cls/OcuTalon/Test/Msg/Catalog.cls` lists `7d7df9521` (fix(23.13): the incident timeline follows EmailOut's answer for a partner warning, DW-1416), so OCT-epic23's `summary.partnerMaySent` is NOT on feature or on this branch (`partnerMaySent` has no hit in `Msg/Catalog/Watch.cls` here). This branch is first to merge, so the count goes 145 to 146 here, as the tasks say. Recorded, not acted on: OCT-epic23 resolves its integrate-forward to 147 (Design Notes, "Merge with OCT-epic23").

**Mutations** (Rule 19; each applied, the named test run warm and shown red, then reverted from a copy taken before it and checked with `cmp`; the class green again after the revert; `git diff --stat` as before after each):
- mutation: `SummaryRunKey`'s not-applied line made `Quit ""` -> `Test.Watch.Summary:TestSettingSavedNotAppliedLine` red ("each run that saved the setting and could not apply it ends with summary.settingSavedNotApplied", and the follows-started, slots and "reads as ruled" asserts) and `Test.Fix.ItemKinds:TestSettingNotApplied` red ("the summary ends the run with summary.settingSavedNotApplied, as ruled").
- mutation: `SummaryRunKey`'s not-applied line taken out -> `Test.Watch.Summary:TestSettingSavedNotAppliedLine` red ("and no summary.settingNotChanged", and the ended-line asserts).
- mutation: the item branch's new block made `If (+run.Completed = 0) && (+run.Unreached > 0) Quit` -> `Test.Watch.Summary:TestItemSavedNotAppliedLine` red (the ended line, the slots and the two texts) and `Test.Fix.ItemKinds:TestItemNotApplied` red ("the summary ends the run with summary.settingSavedNotApplied, as ruled").
- mutation: the item branch's new block taken out -> `Test.Watch.Summary:TestItemSavedNotAppliedLine` red ("and no summary.itemNotChanged", and the ended-line asserts).
- mutation: `$Parameter(class, "ENABLEDSETTING")` and `item` swapped in the slots (`"setting": (item), "target": ($Parameter(class, "ENABLEDSETTING"))`) -> `Test.Watch.Summary:TestItemSavedNotAppliedLine` red ("the item's setting is Enabled and the target is the item, at the run's end", and both texts).
- mutation: the new catalog entry taken out -> `Test.Msg.Catalog` red ("Watch holds exactly its 146 keys", "the fixtures cover exactly the 254 keys of the catalog", and the fixture coverage of `TestEveryKeyOnEveryChannel` on every channel).
- mutation: the entry's "but " taken out of its text -> `Test.Msg.Catalog:TestEveryKeyOnEveryChannel` red ("summary.settingSavedNotApplied on phone is the fixture's text", and on the other channels) and `Test.Watch.Summary:TestSettingSavedNotAppliedLine` red ("and reads as ruled").

- mutation (AC 5, added in review, warm, `cmp` identical after each revert and `git diff --stat` as before, the class green again): `SummaryRunKey`'s not-applied condition widened to `If (+run.Completed = 0) Quit ..#KEYSUMMARYSAVEDNOTAPPLIED` -> `Test.Watch.Summary:TestSettingLines` red ("the rollback that changed nothing ends with summary.settingNotChanged", and two more).
- mutation (AC 5, added in review, same checks): the item branch's condition widened to `If (+run.Completed = 0) {` -> `Test.Watch.Summary:TestKindLines` red ("the resume that changed nothing ends with summary.itemNotChanged").

**Command results** (warm tag e21dw1376iw, lane C, one call each unless noted):
- `OcuTalon.Test.Watch.Summary:TestSettingSavedNotAppliedLine` and `:TestItemSavedNotAppliedLine` passed after the change; whole `OcuTalon.Test.Watch.Summary` passed (after the last revert); `OcuTalon.Test.Msg.Catalog` passed (146 keys, after the last revert); `OcuTalon.Test.Watch.Lifecycle` passed; `OcuTalon.Test.Watch.SettingValues` passed.
- After a production restart (`Ens.Director.RestartProduction` on the throwaway's OcuTalon.Production): `OcuTalon.Test.Fix.ItemKinds:TestItemNotApplied` and `:TestSettingNotApplied` passed (the two were run in one message, against the rule; both passed), and the whole `OcuTalon.Test.Fix.ItemKinds` passed (after a second restart, after the mutations were reverted).
- Run by the build stage after the handoff: fresh `ci/iris.sh shard lane-a@Fix` (tag e21dw1376if): passed, 30 classes, 1073 s, `Test.Fix.ItemKinds` passed on the fresh stack (9.80 s); `cd web && npm test`: 2174 tests, 2174 pass, 0 fail; `bash docker/tests/test-class-rules.sh` and `bash docker/tests/test-boundaries.sh`: all rules passed; the spine lint: 12 findings, all low (the baseline of 12 low).
- The diff holds only the footprint files, no added non-ASCII character, no absolute local path; the catalog text is byte-identical to the approved text, with an ASCII apostrophe.
- The warm stack was removed with `ci/warm.sh down` at the end.

## Review Triage Log

### 2026-11-15 — Review pass
- verdicts: 13 findings — high 0, medium 0, low 7, false 6, maybe-false 0 (one finding, AC 5's missing mutation line, is low and was closed in the pass)
- findings:
  - `[low]` `[reject]` Blind 1: the `(key '= "")` guard in `RunEvents`' setting branch is dead now, and the not-applied condition is written in `SummaryRunKey` and in the item branch — the guard is a defensive check on a public method's contract and the spec forbids changing that branch (it "needs no change"); the spec says "the same condition in both places"; no caller can diverge, the two tests pin both.
  - `[false]` `[reject]` Blind 2: an item run with an empty item stores an empty slot and the catalog refuses it — the branch's other lines (summary.itemSuspended, summary.itemResumed) take the same `item`, `SuspendItem.CheckParameters` requires it, and a stored request without it does not exist; no new exposure (Design Notes, "What the slots are").
  - `[low]` `[reject]` Blind 3: the second run of each doubled test (undo, resume) is pinned by count, adjacency of the first pair and text, not by its own slots — both runs go through the same code and `run.EndedAt`; a per-run slot check adds no mutation that the count of 2 and the texts do not already catch.
  - `[low]` `[reject]` Blind 4: `SavedNotAppliedLine` overwrites `RequestRefs`, ignores Render's status and splits on ": " — the spec's own helper design (the request is the incident's only request; a render failure gives "" and the equality fails; the time of the same day has no ": ").
  - `[false]` `[reject]` Blind 5: the summary text omits the reason and direction — the text is approved verbatim by the Contest Planner and may not be reworded; the reason is in the FixRun and the session line.
  - `[low]` `[reject]` Blind 6: the `Watch.Summary` class header lists the setting ends incompletely and the `SummaryRunKey` doc is one long line — the header was incomplete before this change, and the doc text is the spec's.
  - `[false]` `[reject]` Edge 1: the empty item slot of an item run — same as Blind 2.
  - `[false]` `[reject]` Edge 2: a saved-not-applied setting run whose dry run lacks field or item still has no line — matrix row 7 pins "no ended line, as for every end of such a request today"; the dry run of a rollback always carries them.
  - `[low]` `[patch]` Gap 1: AC 5 has no `mutation:` line — closed in the pass: two mutations (the setting condition widened, the item condition widened) applied warm, `TestSettingLines` and `TestKindLines` red, reverted with `cmp` identical, `Test.Watch.Summary` green again; both lines are in `## Verification`.
  - `[low]` `[reject]` Gap 2: the second run in each doubled Summary test is only partly pinned — same as Blind 3.
  - `[low]` `[reject]` Gap 3: the `(key '= "")` guard is dead — same as Blind 1.
  - `[false]` `[reject]` Gap 4 (Rule 19 check): no unfalsifiable assertion, no unconstructed subject, no state left over — the reviewer's own statement that nothing is wrong; logged as the layer's clean result.
  - `[false]` `[reject]` Intent: the pin sits on the handler with the Check and Carry seams, not on the live restore failure (`InProduction`) — the layer reports it descriptively; the spec's Design Notes ("Why the ItemKinds join") chain DW-1373's and 23.3's live restore-failure tests to this one, so the whole path is pinned.

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** A fix run that saved a setting or an item's flag and could not apply it, with the restore failed (Completed 0, Unreached above 0), now ends in the incident summary with `summary.settingSavedNotApplied`, the Planner's approved text verbatim: "{time}: {setting} on {target} was changed, but the production couldn't apply it." A setting run takes its setting and target from the dry run; an item run takes `Enabled` (the kind's `ENABLEDSETTING`) and the item. No other end changed.

**Files changed.**
- `src/ocutalon/cls/OcuTalon/Msg/Catalog/Watch.cls`: the new entry.
- `src/ocutalon/cls/OcuTalon/Watch/SettingCause.cls`: `KEYSUMMARYSAVEDNOTAPPLIED`, and `SummaryRunKey` returns it for Completed 0 with Unreached above 0.
- `src/ocutalon/cls/OcuTalon/Watch/Summary.cls`: the item branch of `RunEvents` writes the line, and the docs.
- `src/ocutalon/cls/OcuTalon/Test/Msg/Catalog.cls`: the Watch count 145 to 146, the key and the fixture.
- `src/ocutalon/cls/OcuTalon/Test/Watch/Summary.cls`: the two saved-not-applied methods extended (rollback and undo, suspend and resume).
- `src/ocutalon/cls/OcuTalon/Test/Fix/ItemKinds.cls`: the helper `SavedNotAppliedLine` and the asserts of `TestItemNotApplied` and `TestSettingNotApplied`.
- This spec.

**Review.** 13 findings from four layers: patches applied 1 (low: the AC 5 mutation lines, a verification record, no code), deferred 0, rejected 12 with their reasons in the triage log. No high or medium.

**Follow-up review recommended:** false (no high patched; patched counts: high 0, medium 0, low 1).

**Verification.** See `## Verification`: Task 0, the nine mutation lines, the warm classes (`Test.Msg.Catalog`, `Test.Watch.Summary`, `Test.Watch.Lifecycle`, `Test.Watch.SettingValues`, `Test.Fix.ItemKinds` after a production restart), the fresh `lane-a@Fix` shard (30 classes), `npm test` (2174 pass), the class-rules and boundaries scripts, and the spine lint (12 low, the baseline).

**Residual risks.** The count goes 145 to 146 here; OCT-epic23 (DW-1416, `summary.partnerMaySent`) merges second and takes it to 147 at its integrate-forward (Design Notes). The implement handoff ran two ItemKinds methods in one message once (both passed).
