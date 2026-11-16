---
title: 'DW-1373: A suspend or resume that could not be applied is not reported as "Nothing was changed"'
type: 'bugfix'
created: '2026-11-16'
status: 'done'
baseline_revision: '5f2b21ae5e31f4e661b95f16c4169709520eb505'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/spec-23-3-name-the-setting-change-behind-an-incident-and-offer-its-rol.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-23-2-suspend-resume-and-reroute-with-a-dry-run.md'
warnings: []
deferred:
  - summary: >-
      The restore's own EnableConfigItem erring or throwing (the Catch of the item branch) has no test, because the spec forbids a new seam.
    evidence: |-
      The three TestItemUpdateFailure* methods force only UpdateProduction through updateErrors. A restore whose store errs or throws would end notapplied by the code read, but no test pins it (matrix rows 3 and 10 name it).
    location: >-
      src/ocutalon/cls/OcuTalon/Fix/Executor.cls InProduction, item branch restore Try/Catch
    severity: low
---

<intent-contract>

## Intent

**Problem (DW-1373, MED; split from DW-1365 by the Contest Planner's pre-push ruling of 2026-11-15, "own DW for 1.0.12"):** 23.2's suspend and resume report "Nothing was changed" for a change that was saved.
- `Fix.Executor.InProduction`'s item branch (`Fix/Executor.cls:1410-1428`) calls `Ens.Director.EnableConfigItem(production||item, enable)` (L1421), and any error status becomes code `refused`.
- `EnableConfigItem` (`irislib/Ens/Director.cls:1561-1643`) first stores the new flag, then updates the running production:
  - when a System Default Setting `Enabled` applies to the item (L1573), it writes that row by SQL (L1611);
  - otherwise it sets the item's `Enabled` (L1614) and saves the production definition (L1619);
  - it then logs, clears the item's TemporarilyStopped flag (L1629), writes an IRIS audit record (L1639) and returns `UpdateProduction`'s status (L1641).
- `UpdateProduction` never throws (DW-1377): its `$ZT` trap turns any error into a status (L161, L207-209). It fails when it cannot take the runtime lock in 30 s (L177-178), or when an item does not stop within the update timeout (10 s by default, L2015-2018). After `findProductionDifferences` it also marks the production as needing an update (L203).
- So an error after the store gives `refused`. `Fix.Executor.Run` ends that run as could not start with the kind's NOSTART (L586-589), and the session reads `result.itemNotChanged` ("Nothing was changed: OcuTalon couldn't change the item."). But the stored flag did change, and the next production update applies it without approval.

**Approach (the Planner's DW-1365 rule, applied to the item branch the way 23.3 applied it to the setting branch, L1371-1405):**
- **Store, then update, as two steps.** Call `EnableConfigItem(production||item, enable, 0)` (pDoUpdate 0: it stores the flag and does not update). If that returns OK, call `UpdateProduction(GetRunningProductionUpdateTimeout())`, which is the same call `EnableConfigItem` makes at L1641, through the existing `updateErrors` test seam. An error from the first call means nothing was stored, so it stays `refused` and needs no restore.
- **When the update fails after the store, write the earlier value back.** Call `EnableConfigItem(production||item, 'enable, 0)`, then update again through the same seam. IRIS's own call writes the earlier value to the place it wrote the new one: the System Default Setting row when one overrides `Enabled`, else the item definition. 23.3's rollback kinds never edit a System Default Setting row. A suspend already does that when a row overrides `Enabled`, and the restore only undoes its own write.
- **Restore OK:** code `refused`, so `result.itemNotChanged` ("Nothing was changed: {reason}."), which is now true.
- **Restore failed:** code `notapplied`, with the first error as the reason (its sentence, as 23.3: `Watch.ErrorText.Sentence`). The restore fails if its `EnableConfigItem` errs, its update errs, or the restore throws. `Run`'s existing branch then fires (L582-585): Finish failed, Unreached 1, one Action entry, and the session reads the approved `result.settingSavedNotApplied` with setting `Enabled` (the IRIS name of the item's setting) and target the item.
- **Every reader of the result stops claiming "not changed" for such a run:**
  - `Watch.Notice.ResultKey`'s item branch gives `result.settingSavedNotApplied` for Unreached above 0, and `ResultSlots` builds its slots from the item;
  - `Watch.Summary` writes no ended line for it, as 23.3 does for settings (`SettingCause.SummaryRunKey`, L379);
  - the web card's item band (`approval-view.ts` `itemResultView`) shows the same text.

## Boundaries & Constraints

**Always:**
- **Footprint.** Lane C makes these edits under the Planner's DW-1373 assignment (Veto item 2):
  - Lane A:
    - `src/ocutalon/cls/OcuTalon/Fix/Executor.cls`: the item branch of `InProduction`, `InProduction`'s doc (the item bullet and the `updateErrors` sentence), and the class doc's setting-kind bullet (L63-66), widened to item kinds.
    - `src/ocutalon/cls/OcuTalon/Fix/Kind/SuspendItem.cls`: a new parameter `ENABLEDSETTING = "Enabled"` and the class doc's Execute sentence.
    - `src/ocutalon/cls/OcuTalon/Watch/Notice.cls`: `ResultKey`'s item branch, `ResultSlots`, and the class doc's 23.2 sentence (L46-48).
    - `src/ocutalon/cls/OcuTalon/Watch/Summary.cls`: `RunEvents`' item branch and the class doc's item sentence (L12).
    - Tests: `src/ocutalon/cls/OcuTalon/Test/Fix/ItemKinds.cls` and `src/ocutalon/cls/OcuTalon/Test/Watch/Summary.cls`.
  - Lane B:
    - `web/src/app/approvals/approval-view.ts`: `itemResultView` and the `resultView` doc.
    - `web/scripts/approval-view.test.mjs`.
  - This spec.
- The namespace switch stays in `InProduction` (AD-3). The new code there calls only `Ens.Director`, with no OcuTalon class, so the update expression is written inline, as the setting branch writes it (L1374, L1400).
- Use the existing data-only seam. The entry's optional `updateErrors` N makes the first N `UpdateProduction` calls of that entry (the forward update and the restore's) return `$$$ERROR($$$EnsErrGeneral, "the update was refused by the test")` without calling IRIS. No kind's plan sets it (`SuspendItem.Plan` builds `{"id", "action", "item", "production"}`). No `Xecute`, no global seam, and no new seam.
- The forward update is the same call IRIS made before: `UpdateProduction(GetRunningProductionUpdateTimeout())`, with `pForce` 0 and `currentOsUser` 0, as at L1641.
- The approved texts are used verbatim. ObjectScript stays ASCII. Comments state the contract, not review history.
- Every existing test passes unchanged, including `TestLiveSuspendResume`, `TestItemThatCannotBeChanged` and 23.3's DW-1365 tests.

**Never:**
- Add or change a catalog key, sentence, notice, summary key or UI string (Veto item 1 holds the fallback text only in case the reuse is vetoed).
- Change the setting branch, `Fix.Executor.Run`, `Finish`, `CouldNotStart`, `End`, the FixRun or FixResult classes, `Watch.SettingCause`, `IncidentManager`, the Live payload or `Fix.Run` (Holds, Suspended).
- Write `Ens.Config.Item.Enabled` or a `Ens.Config.DefaultSettings` row directly from product code. Every write of the flag goes through `EnableConfigItem`.
- Retry the forward update, or call `UpdateProduction` with `pForce` 1.
- Delete, skip or weaken a test.

## I/O & Edge-Case Matrix

"Stored flag" means where IRIS keeps the item's `Enabled`: a System Default Setting row `Enabled` that applies to the item, else the item definition's `Enabled`. The code is the entry's code in `InProduction`, and the result is what the session, the summary and the card show.

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| 1 Update OK | Approved suspend, item still enabled; `EnableConfigItem(…, 0, 0)` OK, `UpdateProduction` OK | `done`; Completed 1; `result.itemSuspended` (resume: `result.itemResumed`); summary `summary.itemSuspended`. As today. | none |
| 2 Update fails, restore OK | Store OK, the update errs (runtime lock busy 30 s, an item that does not stop in its UpdateTimeout; the test seam `updateErrors` 1) | The earlier flag is written back with `EnableConfigItem(…, 'enable, 0)` and the production updated again: OK. `refused`, then could not start with the kind's NOSTART, `result.itemNotChanged`: "Nothing was changed: OcuTalon couldn't change the item.", summary `summary.itemNotChanged`. One Type 3 `LOGCOPY` warning with the first error, as today. | restore inside its own Try |
| 3 Update fails, restore fails | Store OK, the update errs, and then the restore's `EnableConfigItem` errs, or its update errs (`updateErrors` 2), or the restore throws | `notapplied`, reason = the first error's sentence; Finish failed with Total 1, Completed 0, Skipped 0, Unreached 1 and that reason; one Action entry (result failed); `result.settingSavedNotApplied`: "Enabled on {item} was changed, but the production couldn't apply it: {reason}. Ask me to check the item before you try again."; no summary ended line; the card shows the same band. | the restore's Catch turns a throw into a failed restore |
| 4 Store fails | `EnableConfigItem(…, 0)` errs: the production is not registered, a business process with PoolSize 0, `%Save` fails | Nothing was stored: `refused`, no restore, `result.itemNotChanged`. As today. | none |
| 5 Item gone | The id no longer names the item of the production | `gone`, skipped "{item} is no longer in the production", `result.itemSkipped`. Unchanged, and `EnableConfigItem` is not called. | none |
| 6 Already in the wanted state | The effective `Enabled` (System Default Setting first) already is the action's | `changed`, skipped "{item} changed since the dry run", `result.itemSkipped`. Unchanged, and `EnableConfigItem` is not called. | none |
| 7 A System Default Setting `Enabled` applies | The row overrides the definition's flag | The store and the restore both write that row (IRIS's SQL at `Director.cls:1611`), and the definition is untouched. Otherwise rows 1 to 3. | as rows 1 to 3 |
| 8 Production not running at the update | Stopped between Run's check and the update | `UpdateProduction` returns OK without updating ("No Production is running", L182-183), so `done`; the stored flag applies at the next start. As today. | none |
| 9 Exception thrown in the item branch outside the restore | For example `<PROTECT>` while opening the item | `error`, could not start with the kind's NOSTART. As today. After a store, only `UpdateProduction` runs, and it does not throw. | the branch's existing Catch |
| 10 Restore after someone else changed the flag | Between the store and the restore another job set the flag | The restore's `EnableConfigItem` answers "already …" or saves over the other change. In the first case: row 3 (notapplied, "Ask me to check the item"). | as row 3 |

</intent-contract>

## Code Map

Line numbers are at the baseline `d1414c370`.

- `Fix/Executor.cls`:
  - `Include (EnsConstants, EnsErrors)` at L1, which gives `$$$EnsErrGeneral`.
  - Class doc, setting-kind bullet L63-66 (the 23.3 restore described for setting kinds).
  - `Run` L506: the `notapplied` branch L582-585 (Finish failed with Unreached and the reason), and the could-not-start branch L586-589.
  - `CouldNotStart` L745, `Finish` L776 (redacts the reason; End, Close, Audit, Report), `Audit` L909, `ActionTarget` L959 (an item kind's Action target).
  - `InProduction`:
    - Doc L1286-1312: the setting bullet with the restore and the `updateErrors` sentence L1298-1306, and the item bullet L1307-1309.
    - The method starts at L1313.
    - Setting branch: save L1371, the seam and update L1374, the restore block L1380-1405 (its update L1400, `notapplied` L1404).
    - Item branch L1410-1428: the SDS read L1416, the state test, `EnableConfigItem` L1421, `refused` L1424-1426.
    - The unreached push, with `Watch.ErrorText.Sentence` for `notapplied`, L1499-1507. `SkipReason` L1516.
- `Fix/Kind/SuspendItem.cls`: class doc L7-9 (Execute through `InProduction` and `EnableConfigItem`), `ENABLE` L30, `NOSTART` L34, `Plan` (the plan entry shape). `ResumeItem` only sets `NAME` and `ENABLE` 1.
- `Watch/Notice.cls`:
  - Class doc L46-48.
  - `KEYITEM*` L137-143.
  - `ResultKey` L431: the setting branch L448, the item branch L449-453.
  - `ResultSlots` L474: the SettingCause dispatch L479, the item keys L499-513.
- `Watch/SettingCause.cls` (read only here): `KEYSAVEDNOTAPPLIED` L47; `ResultKey` L317 (Unreached above 0 gives saved-not-applied, L320); `IsResultKey` L327; `ResultSlots` L337 (needs `extra.setting`, `extra.target` and a reason); `SummaryRunKey` L377 (no line for Completed 0 with Unreached above 0, L379).
- `Watch/Summary.cls`: class doc L12; `RunEvents` item branch L205-209 (the key L207).
- `Watch/IncidentManager.cls` (no change): `ResultNotice` L1757 and `ResultExtra` L1770, which gives an item kind `{"item", "production", "to"}`.
- `Live/Payload/Incident.cls` (no change): L203 carries `run.Unreached` into the card's result.
- `Msg/Catalog/Watch.cls` (no change): `result.itemNotChanged` L890-896 and `result.settingSavedNotApplied` L1268-1276.
- Web:
  - `web/src/app/approvals/approval-view.ts`: the `resultView` doc L550-577 (item bullet L561-563), `itemResultView` L650-683, and `settingResultView`'s unreached band L700-701 (the model).
  - `web/scripts/approval-view.test.mjs`: the item-kind cases L200-240 (the `item(...)`/`ran(...)` helpers).
- Tests:
  - `Test/Fix/ItemKinds.cls`: `ITEM` = `OrdersForReview`; `TestLiveSuspendResume` L180; `TestItemThatCannotBeChanged` L343; `TestSettingNotApplied` L395 (the canned model); helpers `Handle`, `Last`, `Request`, `ItemStates`, `ItemId`.
  - `Test/Watch/Case.cls`: `ITEMNAME` = `OrdersToWarehouse` L157; `DisabledItems` L160 and `ItemDefaultSet` L163, cleaned by `OnAfterOneTest`; `SetItemEnabled` L1329; `SetItemDefault` L1350 (writes `^Ens.Config.DefaultSettingsD(production, item, "*", "Enabled")` in OCUORDERS).
  - `Test/Watch/Rollback.cls`: `TestUpdateFailureRestores` L834 and `TestUpdateFailureNotApplied` L852, the live models, with `Top("Ens_Util.Log", ...)` and `LogSince`.
  - `Test/Watch/Summary.cls`: `TestKindLines` L698 and `TestSettingSavedNotAppliedLine` L862 (the model).
- IRIS (`irislib`, read only), verified at the baseline:
  - `Ens/Director.cls` `EnableConfigItem` L1561:
    - parse and open L1563-1565;
    - `findItemByName` L1568;
    - the PoolSize 0 refusal L1570;
    - the SDS read L1573-1580;
    - the "already" refusal L1582;
    - other same-name enabled items disabled L1586-1601;
    - SDS SQL `UPDATE` L1611 or `tFoundItem.Enabled` L1614;
    - `%Save` L1619;
    - log L1622-1626, TempStop kill L1629, audit L1639;
    - `Quit:pDoUpdate ..UpdateProduction(..GetRunningProductionUpdateTimeout(),,,currentOsUser)` L1641, else `Quit tSC` L1642.
  - `UpdateProduction` L159-209: `$ZT` L161, the lock L177-178, not running L181-183, the dirty mark L203, Trap L207-209. `GetRunningProductionUpdateTimeout` L2015.
  - `Ens/Config/Production.cls` `findItemByName` L722 / `findItemIdByName` L736: it prefers the running item, then an enabled one.

## Tasks & Acceptance

**Task 0 (measure first, on a lane-C throwaway, before any product edit except where an item says after; record each result under `## Verification`; never a dev slot, Rule 21):**
- Put the probes in one scratch class (e.g. `ZzScratch.Dw1373`) in your own scratchpad. Load it into the throwaway only, and never commit it. Every call runs in OCUORDERS on `OrdersForReview`, unless the item says otherwise. Put each item back after it: the item enabled, any System Default Setting row removed, and the production up to date.
1. **The store without the update.** Record these:
   - `EnableConfigItem("<Orders production>||OrdersForReview", 0, 0)`: its status, the definition's stored `Enabled` (now 0), `Ens.Director.ProductionNeedsUpdate(.reason)` (expect 1 and a reason), and whether the item's job still runs (`Ens.Director.IsItemRunning`, or `Watch.Reader.Items`).
   - Then `EnableConfigItem(…, 1, 0)` and `UpdateProduction(GetRunningProductionUpdateTimeout())`: the statuses, `ProductionNeedsUpdate` (expect 0), and the Ens event-log lines the four calls wrote.
2. **A real update failure, the old call (the defect).** From a background job (`JOB`) in OCUORDERS, hold `Lock +^Ens.Runtime` (`$$$EnsRuntime`, `Ensemble.inc:116`) for 40 s. Then, in the probe, while the lock is held:
   - call `EnableConfigItem("…||OrdersForReview", 0)` (pDoUpdate 1), timing it;
   - record the status's `GetErrorText` (expect `ERROR <Ens>ErrCanNotAcquireRuntimeLock: …` after about 30 s) and `##class(OcuTalon.Watch.ErrorText).Sentence` of it;
   - record the stored `Enabled` (expect 0: the flag changed although the call failed) and `ProductionNeedsUpdate`.
   - Then put the item back.
   - If the call returns OK, or the stored flag is still 1, stop with `## Clarification Needed`: the defect is not as read.
3. **The System Default Setting path.** For `OrdersToWarehouse`, write the row as `Case.SetItemDefault(1)` does (the global, `$ListBuild(1, "", 0)`). Then:
   - call `EnableConfigItem("…||OrdersToWarehouse", 0, 0)` and record the row's value (expect 0) and the definition's `Enabled` (expect unchanged);
   - call `EnableConfigItem(…, 1, 0)` and record the row's value (expect 1);
   - run `UpdateProduction` and confirm the item still runs.
   - If IRIS's SQL `UPDATE` does not find a row written straight to the global, record that, and have the test write the row through `Ens.Config.DefaultSettings` `%New`/`%Save` (as `Test.Watch.SettingHistory.SaveDefault`). Record which.
4. **The restore path with a real failure (after the Execution tasks; restart the production first, so FixExecutor's job holds the new code):**
   - (a) Hold the lock 40 s, as in item 2, and call the new `Fix.Executor.InProduction` with the plan entry `{"id", "action": "disable", "item": "OrdersForReview", "production"}` (no `updateErrors`). Expect code `refused`: the forward update fails at about 30 s, and the restore's update gets the lock at about 40 s. Record the timing, the code, the stored `Enabled` (expect 1) and the event-log lines ("Disabled item", "Enabled item", one "updating").
   - (b) The same with the lock held 75 s. Expect `notapplied` with the reason "Can not acquire runtime lock, timeout = 30" (or IRIS's exact sentence; record it) at about 60 s. Record the stored `Enabled`: 1 if the restore's store worked.
   - Each call stays under the 10-minute cap. If (a) does not give `refused` with the flag back, do not push; stop with `## Clarification Needed`.

**Execution:**
- [ ] `Fix/Kind/SuspendItem.cls`:
  - New `Parameter ENABLEDSETTING = "Enabled";`, with the doc: "The item's setting that the kind changes, by its IRIS name: Ens.Config.Item Enabled, or the System Default Setting Enabled that overrides it. The result of a change that was stored and could not be applied names it (result.settingSavedNotApplied)."
  - In the class doc's Execute sentence, replace "and calls Ens.Director.EnableConfigItem there" with: "and calls Ens.Director.EnableConfigItem there, stores the flag and updates the production; when the update fails it puts the earlier flag back (see Fix.Executor)".
- [ ] `Fix/Executor.cls` `InProduction`, the item branch: replace the `Else` at L1420-1427 with the code below. `saved`, `updates` and `restoreError` are the setting branch's local names, set again for each entry.
  ```
  } Else {
  	Set sc = ##class(Ens.Director).EnableConfigItem(entry.production_"||"_entry.item, enable, 0)
  	Set saved = $$$ISOK(sc)
  	Set updates = 0
  	If saved Set sc = <the setting branch's $Select of L1374, byte for byte>
  	If $$$ISOK(sc) {
  		Set code = "done"
  	} Else {
  		Set code = "refused"
  		Set detail = $SYSTEM.Status.GetErrorText(sc)
  		If saved {
  			#; the update failed after the flag was stored: the earlier flag is stored again, where EnableConfigItem keeps it, and the production is updated again
  			Try {
  				Set sc = ##class(Ens.Director).EnableConfigItem(entry.production_"||"_entry.item, 'enable, 0)
  				If $$$ISOK(sc) Set sc = <the same $Select>
  			} Catch restoreError {
  				Set sc = restoreError.AsStatus()
  			}
  			If $$$ISERR(sc) Set code = "notapplied"
  		}
  	}
  }
  ```
  - The unreached push (L1499-1507) already handles `notapplied`, with the reason, for every entry shape. No change there.
  - `InProduction`'s doc:
    - The item bullet (L1307-1309) ends: "…and Ens.Director.EnableConfigItem(production||item, enable, 0) stores the flag where IRIS keeps it (the item definition, or the System Default Setting Enabled that overrides it), and Ens.Director.UpdateProduction updates the running production. When the update fails after the store, EnableConfigItem(production||item, 'enable, 0) stores the earlier flag again and the production is updated again, with the codes of a setting change: refused when that works, notapplied with reason when it does not."
    - The `updateErrors` sentence (L1305-1306) moves to after the item bullet and reads: "A setting or item entry's optional "updateErrors" N, which only a test sets (no kind's plan has it), makes the first N calls of UpdateProduction for that entry answer an Ens error, as UpdateProduction's own are, without calling it."
  - Class doc L63: "A kind whose target is a setting (TARGETTYPE setting, Story 23.3)" becomes "A kind whose target is a setting or an item (TARGETTYPE setting, Story 23.3; TARGETTYPE item, DW-1373)". The bullet's last clause becomes: "and the session reads result.settingSavedNotApplied (Watch.SettingCause ResultKey; for an item kind Watch.Notice ResultKey, with the setting Enabled)."
- [ ] `Watch/Notice.cls`:
  - `ResultKey`'s item branch (L449-453): after the Completed line, add `If +result.Unreached > 0 Quit ##class(OcuTalon.Watch.SettingCause).#KEYSAVEDNOTAPPLIED`.
  - `ResultSlots`, just before the SettingCause dispatch (L479): when the key is `KEYSAVEDNOTAPPLIED`, `..Text(extra.%Get("setting"))` is "", and `..Text(extra.%Get("item"))` is not, set `extra = {"setting": (SuspendItem.#ENABLEDSETTING), "target": (that item)}`. The dispatch then builds `{setting, target, reason}`, and refuses a missing reason as it does today. A setting kind's extra always has `setting`, so it is unaffected.
  - Class doc L47: after "result.itemSkipped when the re-check skipped it", insert "result.settingSavedNotApplied (setting Enabled, target the item) when the item's flag was stored and the production could not apply it or have the earlier flag back (Unreached above 0),".
- [ ] `Watch/Summary.cls` `RunEvents`' item branch: before the key (L207), add `If (+run.Completed = 0) && (+run.Unreached > 0) Quit`. Such a run has no ended line, because summary.itemNotChanged would be false and no approved summary text exists (as `SettingCause.SummaryRunKey`). Add the same clause to the class doc's item sentence (L12): "(none for a run that stored the flag and could not apply it)".
- [ ] `web/src/app/approvals/approval-view.ts`:
  - `itemResultView`: after the `reason === ''` test and before the skipped one, add `else if ((numberOf(result.unreached) ?? 0) > 0) { if (item === '') return undefined; key = 'result.settingSavedNotApplied'; slots = { setting: ENABLED_SETTING, target: item, reason }; }`.
  - Add `const ENABLED_SETTING = 'Enabled'` with a doc line naming `Fix.Kind.SuspendItem ENABLEDSETTING`, as `PARTNER_NOT_SET_UP` names its source.
  - The `resultView` doc's item bullet (L561-563) gains: "else, with a reason, `unreached` above 0 is result.settingSavedNotApplied (setting Enabled, target the item, reason), partial, `triangle-alert`".
- [ ] Tests (below), each with a header bullet in its class doc.
- [ ] This spec: the `## Verification` records (Task 0 and the mutation lines).

**Tests:**
- `Test/Fix/ItemKinds.cls`, live. These need the running Orders production, and run fresh like the class. They call `Fix.Executor.InProduction` directly in this process, as `Test.Watch.Rollback` does. Add a helper `ActionEntry(action, item, updateErrors)`. It returns `{"id": (..ItemId(item)), "action": (action), "item": (item), "production": (..#ORDERSPRODUCTION), "updateErrors": (updateErrors)}`.
  - `TestItemUpdateFailureRestores` (AC 1):
    - Mark the event log (`..Top("Ens_Util.Log", ..#ORDERS)`; promote `Rollback`'s `Top`/`LogSince` to `Case` if they are not there already, or copy them as private helpers).
    - Disable `OrdersForReview` with updateErrors 1:
      - done|skipped|unreached is `0|0|1`, and the entry is `refused`;
      - `ItemStates()` is unchanged ("the earlier flag was stored again");
      - the log since the mark has one "Disabled item 'OrdersForReview'" line, one "Enabled item 'OrdersForReview'" line, and exactly one "Production '<Orders>' updating" line from this job ("the restore updated the running production once").
    - Then `SetItemEnabled(0, ..#ITEM)`, and enable with updateErrors 1:
      - `refused`, and the item stays disabled ("a resume is restored the same way").
    - The `OnAfterOneTest` cleanup enables it again.
  - `TestItemUpdateFailureNotApplied` (AC 2):
    - Disable with updateErrors 2. Unreached is `1|notapplied|the update was refused by the test` (no `ERROR <Ens>` prefix), and `ItemStates()` is unchanged (the restore's store worked; only its update was refused).
    - Control: the same entry with updateErrors 0 is `1|0|0` (done), and `OrdersForReview=0` is in `ItemStates()`. Add the item to `DisabledItems` before the call.
  - `TestItemUpdateFailureRestoresDefault` (AC 3, matrix 7):
    - Set `SetItemDefault(1)` for `OrdersToWarehouse` (`ITEMNAME`), or the class write if Task 0 item 3 says so. Read the definition's stored `Enabled` of the item.
    - Disable `OrdersToWarehouse` with updateErrors 1:
      - `refused`;
      - the row's value is 1 again ("the restore wrote the System Default Setting it changed");
      - the definition's `Enabled` is as read ("and left the definition alone").
    - `OnAfterOneTest` removes the row.
  - `TestItemNotApplied` (AC 4), canned, through the probe's handler, modelled on `TestSettingNotApplied`:
    - Use `suspend_item`, parameters `{"item": ITEM}`, `CheckIs` passed 7, and `CarryIs` `{"copies":[],"skipped":[],"unreached":[{"id":7,"code":"notapplied","reason":"The update timed out"}]}`.
    - The last FixResult is `1|1|0|0|1|The update timed out`, the request is failed, and one more Action entry `suspend_item|failed` is written.
    - `Notice.ResultKey` gives `result.settingSavedNotApplied`. `Notice.ResultSlots(key, result, {}, .sc, {"item": ITEM, "production": "Orders", "to": ""})` is OK and renders (phone) "Enabled on OrdersForReview was changed, but the production couldn't apply it: The update timed out. Ask me to check the item before you try again."
    - With `resume_item` the key is the same.
    - With the reason "", `ResultSlots` errs.
- `Test/Watch/Summary.cls`: `TestItemSavedNotAppliedLine` (AC 5), modelled on `TestSettingSavedNotAppliedLine`:
  - a `suspend_item` request (state failed) whose FixRun is Completed 0, Skipped 0, Unreached 1 and Reason "The update timed out";
  - the closed incident's keys have `summary.requestedSuspend` and `summary.fixStarted` once each, and no `summary.itemNotChanged` or `summary.itemSuspended`.
- `web/scripts/approval-view.test.mjs` (AC 6):
  - `item('suspend_item', ran({ completed: 0, unreached: 1, reason: 'The update timed out' }), { state: 'failed' })` deep-equals `{ key: 'result.settingSavedNotApplied', text: "Enabled on OrdersForReview was changed, but the production couldn't apply it: The update timed out. Ask me to check the item before you try again.", tone: 'partial', icon: 'triangle-alert', audit: AUDIT }`, with `ITEM` as the test's own constant;
  - the same for `resume_item`;
  - with `{ item: undefined }` it is `undefined`.

**Acceptance Criteria:**
1. Given a suspend or a resume whose production update fails after the flag was stored, and whose restore works, then the earlier flag is stored again through `EnableConfigItem`, the production is updated once more, and the entry is `refused`, so the run reads "Nothing was changed: …" truthfully.
   - mutation: the item branch's restore `If saved {` made `If 0 {` -> `TestItemUpdateFailureRestores` red ("the earlier flag was stored again").
   - mutation: the restore's `'enable` made `enable` -> red (the entry is `notapplied`, not `refused`).
   - mutation: the restore's update replaced by `$$$OK` -> red ("the restore updated the running production once").
2. Given the same with a restore that fails too, then the entry is `notapplied` with the first error's sentence as its reason.
   - mutation: the item branch's `If $$$ISERR(sc) Set code = "notapplied"` removed -> `TestItemUpdateFailureNotApplied` red (the entry is `refused`).
3. Given a System Default Setting `Enabled` that applies to the item, then the restore writes that row back and leaves the definition alone.
   - mutation: the restore's `EnableConfigItem(…, 'enable, 0)` replaced by `Set item.Enabled = 'enable` and `Set sc = item.Production.%Save()` -> `TestItemUpdateFailureRestoresDefault` red ("the restore wrote the System Default Setting it changed").
4. Given an item run whose entry is `notapplied`, then the run ends failed through Finish with Unreached 1 and the reason, one Action entry is written, and the session reads `result.settingSavedNotApplied` with setting Enabled and target the item, verbatim.
   - mutation: `Notice.ResultKey`'s new `Unreached` line removed -> `TestItemNotApplied` red (the key is `result.itemNotChanged`).
   - mutation: `Notice.ResultSlots`' item mapping removed -> red ("its slots are built").
5. Given such a run in a closed incident, then the summary has no ended line for it.
   - mutation: the new `Unreached` test of `Summary.RunEvents` removed -> `TestItemSavedNotAppliedLine` red (summary.itemNotChanged appears).
6. Given such a run on the incident card, then its band is `result.settingSavedNotApplied`, and no band shows without the item.
   - mutation: `itemResultView`'s unreached test made `false` -> `approval-view.test.mjs` red (the band is `result.itemNotChanged`).
7. Every existing test passes unchanged:
   - `Test.Fix.ItemKinds` (including `TestLiveSuspendResume`, which now runs the split store-then-update for real, and `TestItemThatCannotBeChanged`);
   - `Test.Watch.Rollback` (23.3's DW-1365 tests);
   - `Test.Watch.Summary` and `Test.Fix.Executor`;
   - `npm --prefix web test`.

## Design Notes

**Why `EnableConfigItem(…, 0)` and not the definition.** IRIS keeps the flag in one of two places (`Director.cls:1573-1615`). `EnableConfigItem` picks the place by the same SDS read that `InProduction` already does at L1416, and it writes the earlier value back to that same place. Writing `item.Enabled` directly would leave an overriding System Default Setting row changed (AC 3 pins this). With pDoUpdate 0 it is IRIS's own store, with its own log line, TemporarilyStopped clear and audit record. Calling `UpdateProduction` ourselves is what lets the `updateErrors` seam force the failure, with no new seam.

**Truthfulness of the reused text.** "Enabled on {item} was changed, but the production couldn't apply it: {reason}. Ask me to check the item before you try again."
- "Enabled" is the item setting's own IRIS name, the one the Management Portal shows. It is a slot value, as 23.3's rows carry `RetryInterval` or `ZzFixtureNote`.
- "was changed" is true: the stored flag (the definition's, or the System Default Setting's) was changed.
- "couldn't apply it" is true: the update failed.
- When the restore's store worked and only its update failed, the stored flag is the earlier one again, but the production may have applied part of either update. The Planner accepted the same wording for 23.3 (23.3 review, Blind 2), and "Ask me to check the item" covers it.
- The suspend and resume wording ("suspend", "resume") does not appear, so the sentence says less than `result.itemSuspended` but nothing false.

**Fallback (only if the Planner vetoes the reuse; not proposed):** a new key `result.itemSavedNotApplied`, slots `item` (text) and `reason` (sentence): "The change to {item} was saved, but the production couldn't apply it: {reason}. Ask me to check the item before you try again." It would need the catalog, `Test.Msg.Catalog`, the web catalog and its slot types, as 23.3's P4 did.

**What stays as it is (residual, accepted, as for 23.3):**
- A not-applied run has Completed 0, so `Fix.Run.Suspended`/Holds (Story 23.9) does not count it as OcuTalon's suspend. If the production later applies a stored disable, `Checks` reports the item as disabled by someone else, which is a true alert. The user was already told to check the item.
- A check that runs between the store and the restore can see the stored flag for up to the update's wait, 30 s for the lock plus the UpdateTimeout. 23.2 rejected the same window for the success path (23.2 review, edge 3).
- `EnableConfigItem` clears the item's TemporarilyStopped runtime flag (L1629), and a restore does not set it again. That flag is runtime state, which the next temporary stop sets.
- Two items with one name both enabled (L1586-1601) is a production IRIS cannot run, so the restore covers the one item.
- If the SDS `UPDATE` at L1611 fails, IRIS ignores its SQLCODE: the store returns OK with nothing stored, and the update finds no difference. This is pre-existing IRIS behaviour and the inverse of this defect, so it is not handled here.
- The summary has no ended line for a not-applied run, the same gap as 23.3's deferred item. A summary text for "saved, not applied" would cover both, and is a Planner item for later.

**AD:** no sentence is needed. AD-16's "Item fixes" sentence (spine L178: the switching method "enable[s] or disable[s] an item (`Ens.Director.EnableConfigItem`)") stays true, and 23.3 added no AD sentence for the same restore. If the Planner wants a record anyway, the sentence to add after it would be: "When the production's update fails after a fix stored a setting or an item's Enabled flag, the executor stores the earlier value again and updates once more; only if that fails does the run end failed with result.settingSavedNotApplied (DW-1365, DW-1373)."

**Ledger inbox:** DW-1373 (this spec). Its status line is recorded per the run's DW process at merge, with Task 0's figures, through `ledger.sh append`.

## Veto items

| # | Gate item | What | Recommendation |
|---|-----------|------|----------------|
| 1 | (a) New public text | None. A not-applied suspend or resume reuses the approved `result.settingSavedNotApplied` verbatim, with setting `Enabled` (the item setting's IRIS name, a slot value) and target the item: "Enabled on OrdersForReview was changed, but the production couldn't apply it: {reason}. Ask me to check the item before you try again." A restored one keeps the approved `result.itemNotChanged` ("Nothing was changed: OcuTalon couldn't change the item."), which is now true. No summary text is added: such a run has no ended line, as in 23.3. Fallback text, only on a veto: Design Notes. | Approve the reuse. |
| 2 | (b) Cross-lane edits | `Fix.Executor`, `Fix.Kind.SuspendItem`, `Watch.Notice`, `Watch.Summary`, `Test.Fix.ItemKinds` and `Test.Watch.Summary` are Lane A. `web/src/app/approvals/approval-view.ts` and `web/scripts/approval-view.test.mjs` are Lane B (`web/`). Lane C makes the edits under the Planner's DW-1373 assignment. At plan time no unmerged `OCT-*` branch touches these files. | Grant. |
| 3 | (c) Stored data or schema | None. FixRun `Unreached` and `Reason`, and the FixResult, already carry the not-applied end (23.3). No class, property or storage change. Tests change `OrdersForReview`'s flag and a System Default Setting row of `OrdersToWarehouse` in OCUORDERS on throwaways only (Rule 21), restored after each test. | Approve, with no migration. |
| 4 | (d) Architecture change | None. AD-16's "Item fixes" sentence stays true. An optional record sentence is in Design Notes, verbatim, if wanted. | Approve with no AD change. |
| 5 | (e) Product behaviour change | When a suspend or resume's production update fails after the flag was stored, the executor stores the earlier flag again (through `EnableConfigItem`, so in the definition or in the overriding System Default Setting row) and updates again. If that works, the run reads "Nothing was changed: OcuTalon couldn't change the item." (now true). If it fails, the request is failed with Unreached 1 and the production's error, one Action entry is written, the session and the card read `result.settingSavedNotApplied`, and the summary has no ended line. The forward call is now `EnableConfigItem(…, 0)` then `UpdateProduction` with the same timeout, the same call IRIS made. A restore adds one more "Enabled/Disabled item" event-log line and one more IRIS configuration audit record. | Approve. |
| 6 | Design beyond the ruling | Splitting the forward call (pDoUpdate 0) so the existing seam can force the failure. The summary's missing ended line and the card band, so that no reader says "not changed". | Approve. |

## Public text

None new. Approved texts used verbatim (`Msg/Catalog/Watch.cls`):
- `result.itemNotChanged` (Story 23.2): "Nothing was changed: {reason}."
- `result.settingSavedNotApplied` (Story 23.3, DW-1365 ruling): "{setting} on {target} was changed, but the production couldn't apply it: {reason}. Ask me to check the item before you try again." For an item kind, `setting` is `Enabled` and `target` is the item.

**Findability:** the card's band for a not-applied suspend or resume is the existing partial band (`triangle-alert`).

## Verification

Use a lane C throwaway only (Rule 21), never a dev slot. Set these on every `ci/iris.sh` and `ci/warm.sh` call: `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=21 stage=<stage>'`.
- Warm runs add `OCUTALON_WARM=1 OCUTALON_RUN_TAG=<warm tag>`.
- Fresh runs leave `OCUTALON_WARM` unset. `Test.Fix.ItemKinds` and `Test.Watch.Rollback` need the production's jobs to hold the new code, so they run fresh, or warm after a production restart.
- One test class (or `Class:Method`) per foreground call, `timeout: 600000`, each under about 3 minutes. Split by method where needed. Never run two test calls in one message.

**Commands:**
- (once) `ci/warm.sh up` with the warm tag, then Task 0 items 1 to 3, before any product edit.
- (loop) Warm, after a production restart, each expected to pass:
  - `ci/iris.sh class OcuTalon.Test.Fix.ItemKinds:<Method>` for the four new methods;
  - `ci/iris.sh class OcuTalon.Test.Watch.Summary`;
  - `npm --prefix web test`.
- (once) Task 0 item 4 on the warm stack, after the product change is compiled and the production restarted.
- (once) Fresh, each expected to pass:
  - `OcuTalon.Test.Fix.ItemKinds` (whole class, or split by method);
  - `OcuTalon.Test.Watch.Rollback`: `TestUpdateFailureRestores`, `TestUpdateFailureNotApplied`, `TestUpdateFailureRestoresRemoval` and `TestUpdateFailureRestoresInsert`;
  - `OcuTalon.Test.Fix.Executor`.
- (once) `OcuTalon.Test.Msg.Catalog` warm (unchanged keys; a guard).
- (once) `bash docker/tests/test-boundaries.sh`, then `bash docker/tests/test-class-rules.sh`, one per call: each exits 0.
- (once) `git diff --name-only d1414c370` lists only the footprint files. No added line holds a non-ASCII character or an absolute local path.
- (once, at the end, also after a failure) `ci/warm.sh down` with the warm tag.

**Mutations (Rule 19):**
- Write one `mutation:` line per mutation under AC 1 to 6, as `mutation: <change> -> <test that went red>`.
- Revert each byte for byte (`cmp` against a copy taken before it), and check that `git status --short` and `git diff --stat` are as before.

**Task 0 records** (lane C warm throwaway, tag e21dw1373iw, IRIS build of the base image; probe class ZzScratch.Dw1373 loaded into the throwaway only, never in the tree; every item put back: OrdersForReview enabled, the System Default Setting row removed, production up to date):
1. The store without the update, `OrdersForReview`: `EnableConfigItem(prod||OrdersForReview, 0, 0)` returned OK; the definition's stored `Enabled` was 0; `ProductionNeedsUpdate` was 1 with the reason "Job '3340' needs to be terminated."; the item's job still ran (`Ens.Job:Enumerate` count 1). `EnableConfigItem(..., 1, 0)` returned OK: stored `Enabled` 1, `ProductionNeedsUpdate` 0. `UpdateProduction(GetRunningProductionUpdateTimeout())` returned OK, `ProductionNeedsUpdate` 0, the job still ran. The Ens event log of the four calls: "Disabled item 'OrdersForReview' in Production '<Orders>'." (Type 4), "Enabled item 'OrdersForReview' in Production '<Orders>'." (Type 4), "Production '<Orders>' updating... (UpdateTimeout: 10s, Force flag: 0)" (Type 4), "Production '<Orders>' is up-to-date." (Type 4).
2. The defect, the old call (lock `^Ens.Runtime` held 40 s by a JOB): `EnableConfigItem(prod||OrdersForReview, 0)` took 30.0 s and returned `ERROR <Ens>ErrCanNotAcquireRuntimeLock: Could not acquire runtime global lock within timeout '30'`; `Watch.ErrorText.Sentence` of it is "Could not acquire runtime global lock within timeout 30" (the quotes of the text are dropped by the test shell's own doubling; the in-process reason of item 4(b) keeps them, see below). The stored `Enabled` was 0 after the failed call (the flag changed although the call failed) and `ProductionNeedsUpdate` was 1. The failure logged Type 2 lines with the same text. The defect is as read. The item was put back by `EnableConfigItem(..., 1, 0)` and `UpdateProduction`: both OK, stored `Enabled` 1, `ProductionNeedsUpdate` 0.
3. The System Default Setting path, `OrdersToWarehouse`: the row written as `Case.SetItemDefault(1)` does (`^Ens.Config.DefaultSettingsD(prod, item, "*", "Enabled") = $ListBuild(1, "", 0)`). `EnableConfigItem(..., 0, 0)` returned OK and IRIS's SQL `UPDATE` found the row written straight to the global: the row's value was 0 and the definition's `Enabled` stayed 1; `ProductionNeedsUpdate` was 1. `EnableConfigItem(..., 1, 0)` returned OK: the row's value 1, definition 1, `ProductionNeedsUpdate` 0. `UpdateProduction` returned OK and the item's job still ran. So the test writes the row to the global, as `Case.SetItemDefault` does (no `Ens.Config.DefaultSettings` `%Save` needed). The row was killed afterwards.
4. The restore with a real failure, after the product change was compiled and the OcuTalon production restarted (`Fix.Executor.InProduction` called from the probe, plan entry `{"id" (the Ens.Config.Item id, 4), "action": "disable", "item": "OrdersForReview", "production"}`, no `updateErrors`):
   - (a) lock held 40 s: `InProduction` took 39.9 s, done 0, skipped [], unreached `[{"id":"4","code":"refused"}]`. The forward update failed at about 30 s; the restore's update took the lock when it was freed at about 40 s. The stored `Enabled` was 1 and `ProductionNeedsUpdate` 0. The log lines: "Disabled item 'OrdersForReview'" once, "Enabled item 'OrdersForReview'" once, three Type 2 `ErrCanNotAcquireRuntimeLock` lines (the failed forward update, logged by IRIS), "Production ... updating..." once, "Production ... is up-to-date." once.
   - (b) lock held 75 s: `InProduction` took 60.0 s, done 0, skipped [], unreached `[{"id":"4","code":"notapplied","reason":"Could not acquire runtime global lock within timeout '30'"}]` (IRIS's own sentence, the `ERROR <Ens>ErrCanNotAcquireRuntimeLock: ` prefix stripped). The stored `Enabled` was 1 (the restore's store worked); the log: "Disabled item" once, "Enabled item" once, six Type 2 lock lines (two failed updates), no "updating" line. After the lock was freed the item was as before (stored 1, `ProductionNeedsUpdate` 0, the job running).

**Mutations** (Rule 19; each applied, the named test run warm and shown red, then reverted from a copy taken before it and checked with `cmp`; `git status --short` and `git diff --stat` were as before after each):
- mutation: the item branch's restore `If saved {` made `If 0 {` -> `TestItemUpdateFailureRestores` red ("the earlier flag was stored again", "the restore updated the running production once").
- mutation: the restore's `'enable` made `enable` -> `TestItemUpdateFailureRestores` red (the entry is `notapplied`, not `refused`: "as refused").
- mutation: the restore's update replaced by `$$$OK` -> `TestItemUpdateFailureRestores` red ("the restore updated the running production once").
- mutation: the item branch's `If $$$ISERR(sc) Set code = "notapplied"` removed -> `TestItemUpdateFailureNotApplied` red ("as notapplied, with the production's error").
- mutation: the restore's `EnableConfigItem(..., 'enable, 0)` replaced by `Set item.Enabled = 'enable` and `Set sc = item.Production.%Save()` -> `TestItemUpdateFailureRestoresDefault` red ("the restore wrote the System Default Setting it changed").
- mutation: `Watch.Notice` `ResultKey`'s new `Unreached` line removed -> `TestItemNotApplied` red ("the session reads result.settingSavedNotApplied").
- mutation: `Watch.Notice` `ResultSlots`' item mapping removed -> `TestItemNotApplied` red ("its slots are built", the setting-kind slots refuse the extra).
- mutation: the new `Unreached` test of `Watch.Summary` `RunEvents` removed -> `TestItemSavedNotAppliedLine` red ("and no summary.itemNotChanged").
- mutation: `itemResultView`'s unreached test made `false` -> `node --test web/scripts/approval-view.test.mjs` red (the new case: the band is `result.itemNotChanged`).

**Command results** (lane C throwaway tags e21dw1373iw (warm) and e21dw1373if (fresh), both removed at the end; no stack of this stage is up):
- Warm, after a production restart: `OcuTalon.Test.Fix.ItemKinds` (whole class, and each of the four new methods) passed; `OcuTalon.Test.Watch.Summary` passed; `OcuTalon.Test.Watch.Rollback` (whole class, 102 s) passed; `OcuTalon.Test.Msg.Catalog` passed.
- Fresh: `ci/iris.sh shard lane-a@Fix` passed (30 classes, 1061 s), `Test.Fix.ItemKinds` and `Test.Fix.Executor` among them.
- `npm --prefix web test` passed (2174 tests, 0 failed), `web/scripts/initial-bundle.test.mjs` passed (921 kB cap).
- Browser: the approval card's spec is in the Playwright project `cards`, not in sign-in-2 (web/playwright.config.ts), so `ci/iris.sh live cards` was run on a fresh stack after `ci/iris.sh build`: 32 passed (approval-card.spec.ts and incident-card.spec.ts), no browser spec was changed.
- `bash docker/tests/test-boundaries.sh` and `bash docker/tests/test-class-rules.sh`, one per call: all rules passed.
- The spine lint (`.claude/skills/bmad-architecture/scripts/lint_spine.py --workspace` the spine folder; the spine is not edited): 12 findings, all low, as at the baseline.
- The diff holds only the footprint files; no added line holds a non-ASCII character or an absolute local path.

## Review Triage Log

### 2026-11-15 - Review pass
- verdicts: 20 findings - high 0, medium 0, low 13, false 7, maybe-false 0
- findings:
  - `[false]` `[reject]` Blind 1: a restore whose store worked and whose update failed is notapplied and the text says "was changed" - the spec's Design Notes accept this wording (23.3 Blind 2: "Ask me to check the item" covers it); spec-bound, by design.
  - `[false]` `[reject]` Blind 2 and Edge 7: the restore leaves other same-name enabled items changed - the spec lists two enabled items with one name as a production IRIS cannot run (residual, accepted).
  - `[false]` `[reject]` Blind 3, Edge 2 and Edge 6: a failed first EnableConfigItem may leave stored state - Director.cls L1604-1620 shows the System Default Setting branch never sets tSaveProduction, so only the definition branch saves, and a failed %Save stores nothing; the claim "an error from the first call means nothing was stored" holds.
  - `[low]` `[defer]` Blind 4 and Verification gap 1: the restore's EnableConfigItem erring or throwing is not exercised - real, but pinning it needs a new seam, which the spec forbids; recorded under `deferred`.
  - `[low]` `[reject]` Blind 4 (second part): updateErrors gives the same text for the first and second error, so the first-error reason is not told apart - the seam's text is fixed by the spec; changing it is a new seam, and the reason is the first error's by the code read.
  - `[false]` `[reject]` Blind 4 (third part): TestItemNotApplied runs the handler for suspend_item only - the spec asks for the same key with resume_item at the ResultKey level, which the test does.
  - `[low]` `[reject]` Blind 5: the update expression is copied four times - the spec requires it inline and byte for byte (AD-3: no OcuTalon class in the namespace switch), so by design.
  - `[low]` `[reject]` Blind 6: no ended line in the summary, and no resume_item case in TestItemSavedNotAppliedLine - spec-bound (SettingCause does the same, no approved text exists); the Quit is kind-agnostic, so a resume case adds no pin.
  - `[low]` `[reject]` Blind 7: the name Enabled is held in three places - ObjectScript, TypeScript and the test cannot share one constant; the TS doc names its source, as PARTNER_NOT_SET_UP does.
  - `[low]` `[reject]` Blind 8: DefinitionEnabled is unguarded - a missing item raises an error in the test, which fails loudly; not worth a guard.
  - `[false]` `[reject]` Blind 9: LogSince does not filter by job - it reads rows after the floor with their ConfigName, and the job's own lines carry none, as Test.Watch.Rollback's helper does; the test counts only the lines it names.
  - `[low]` `[reject]` Edge 1: an exception from the forward store or update outside the restore - spec matrix row 9 sets it to error as today (after a store only UpdateProduction runs, and it never throws).
  - `[false]` `[reject]` Edge 3: a restore that errs because the flag is already back is notapplied - spec matrix row 10 sets this (notapplied, "Ask me to check the item").
  - `[low]` `[reject]` Edge 4: Unreached above 0 with an empty reason gives no notice - the executor always gives notapplied a reason from the status's sentence, and ResultSlots refuses a missing reason as it does for setting kinds today.
  - `[false]` `[reject]` Edge 5: the System Default Setting row written to the global may not be found by IRIS's SQL UPDATE - Task 0 item 3 measured that it is found (row 1, 0, 1; definition unchanged), and TestItemUpdateFailureRestoresDefault pins it.
  - `[low]` `[reject]` Edge 6 (claims): "restore only undoes its own write" and the TemporarilyStopped flag - same as Blind 2; the flag is runtime state, listed in the spec's residuals.
  - `[low]` `[reject]` Intent-alignment: executor tests call InProduction directly, TestItemNotApplied and the summary test use canned inputs, so no test joins the item branch to the notice in one run - descriptive; the same shape as 23.3's TestSettingNotApplied, and Task 0 item 4 ran the real restore.
  - `[low]` `[reject]` Intent-alignment: other files mention itemNotChanged - read: they are the catalog, tests and the setting dispatcher, none reads an item run's result; the built bundle is gitignored.
  - `[low]` `[reject]` Verification gap, other: the resume half, the item === '' guard and the Unreached-over-Skipped order have no mutation line of their own - they are asserted, and the per-AC mutation lines of Rule 19 are present for AC 1 to 6.
  - `[low]` `[reject]` Verification gap, other: two of the new tests do not assert that the item starts enabled - a disabled start would fail loudly as a skipped entry, not pass.

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** A suspend or resume whose production update fails after the flag was stored now writes the earlier flag back through `EnableConfigItem(..., 'enable, 0)` and updates again. The entry is `refused` (so "Nothing was changed", now true) when that works and `notapplied` when it does not, and a `notapplied` item run reads the approved `result.settingSavedNotApplied` (setting Enabled, target the item) in the session and on the card, with no summary ended line. No new text.

**Files changed.**
- `src/ocutalon/cls/OcuTalon/Fix/Executor.cls`: item branch of `InProduction` (store, update through the `updateErrors` seam, restore in Try) and its docs.
- `src/ocutalon/cls/OcuTalon/Fix/Kind/SuspendItem.cls`: `ENABLEDSETTING` and the Execute sentence.
- `src/ocutalon/cls/OcuTalon/Watch/Notice.cls`: `ResultKey` item branch, `ResultSlots`, class doc.
- `src/ocutalon/cls/OcuTalon/Watch/Summary.cls`: no ended line for Completed 0 with Unreached above 0.
- `web/src/app/approvals/approval-view.ts`: `itemResultView` band and `ENABLED_SETTING`.
- Tests: `Test/Fix/ItemKinds.cls` (four methods, helpers), `Test/Watch/Summary.cls` (`TestItemSavedNotAppliedLine`), `web/scripts/approval-view.test.mjs`.
- This spec.

**Review.** 20 findings from four layers: high 0, medium 0, patched 0. One low deferred (the restore's own store erring or throwing has no test; the spec forbids a new seam). The other 19 are rejected with their reason in the triage log (false 7; low 12, by design, accepted in the spec or not worth a guard).

**Follow-up review recommended:** false (no patch was applied; no high).

**Verification.** See `## Verification`: Task 0 (defect reproduced at 30.0 s; restore at a 40 s lock hold gave `refused` and the flag back, at 75 s `notapplied`), nine mutation lines, the ItemKinds, Summary, Rollback and Catalog classes warm, `lane-a@Fix` fresh (30 classes), `npm test` (2174), the bundle cap, `live cards` (32 passed), the two docker scripts and the spine lint (12 low, baseline).

**Residual risks.** A mid-test failure of the update-failure tests can leave `OrdersForReview` disabled until the next update (only the second part registers it for the cleanup). The restore's own failure branch is pinned only through `updateErrors`.
